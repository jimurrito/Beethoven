defmodule Beethoven.Tracker do
  @moduledoc """
  State tracking for the Beethoven services. Uses Mnesia.
  Tabled named 'Beethoven.Tracker'
  """

  require Logger
  alias Beethoven.Tracker, as: Tracker
  alias Beethoven.Utils

  #
  #
  #
  @doc """
  Starts tracker Mnesia table
  """
  @spec start() :: :ok | :already_exists
  def start() do
    # checks if table already exists
    if Utils.mnesia_table_exists?(Tracker) do
      # add ram copy
      :ok = Utils.copy_mnesia_table(Tracker)
      :already_exists
    else
      Logger.debug("Creating 'Beethoven.Tracker' mnesia table.")

      :mnesia.create_table(Tracker,
        attributes: [:node, :role, :health, :last_change],
        # Sets ram copies for ALL existing nodes in the cluster
        ram_copies: [node() | Node.list()],
        # This is so it works like a queue
        type: :ordered_set
      )

      # Create indexes - speeds up searches for data that does not regularly change
      Logger.debug("Creating Indexes in 'Beethoven.Tracker'")
      :mnesia.add_table_index(Tracker, :node)
      :mnesia.add_table_index(Tracker, :role)
      # Add self to tracker
      :ok = add_self()
      # Subscribe to tracker
      {:ok, _node} = subscribe()
      #
      :ok
    end
  end

  #
  #
  #
  @doc """
  Add self to tracker
  """
  @spec join() :: :ok | :not_started | :copy_error
  def join() do
    if not Utils.mnesia_table_exists?(Tracker) do
      :not_started
    else
      # Add self to tracker
      :ok = add_self()
      # Copy table to local memory
      Utils.copy_mnesia_table(Tracker)
      |> case do
        # Copied table to memory
        :ok ->
          # Subscribe to tracker
          {:ok, _node} = subscribe()
          #
          :ok

        # Failed to copy to memory
        {:error, _error} ->
          :copy_error
      end
    end
  end

  #
  #
  #
  @doc """
  Adds self to BeethovenTracking Mnesia table.
  """
  @spec add_self() :: :ok
  def add_self(roles \\ []) do
    # Add self to tracker
    Logger.debug("Adding self to 'Beethoven.Tracker' Mnesia table.")

    {:atomic, :ok} =
      :mnesia.transaction(fn ->
        #  [:node, :role, :role_num, :health, :last_change]
        :mnesia.write({Tracker, node(), roles, :online, DateTime.now!("Etc/UTC")})
      end)

    :ok
  end

  #
  #
  #
  @doc """
  Subscribe to changes to the BeethovenTracking Mnesia table
  """
  @spec subscribe() :: {:ok, node()} | {:error, reason :: term()}
  def subscribe() do
    # Subscribe to tracking table
    :mnesia.subscribe({:table, Tracker, :detailed})
  end

  #
  #
  #
  @doc """
  Builtin roles
  """
  def builtin_roles() do
    [:been_alloc]
  end

  #
  # DO NOT INCLUDE IN ANY FUN HERE.
  # THIS WILL CAUSE BUGS WHEN LOOKING FOR HOSTED DEFAULT ROLES.
  @doc """
  Removes builtin roles from a list of roles.
  """
  @spec remove_builtins(list()) :: list()
  def remove_builtins(role_list) do
    role_list
    |> Enum.filter(&(Enum.find(builtin_roles(), fn bir -> bir != &1 end) != nil))
  end

  #
  #
  #
  # https://elixirschool.com/en/lessons/storage/mnesia
  @doc """
  Gets roles hosted in the cluster. Provides list of roles - this list is **not** deduplicated.
  """
  @spec get_active_roles() :: list()
  def get_active_roles() do
    #
    fn ->
      #  [:node, :role, :role_num, :health, :last_change]
      pattern = {Tracker, :_, :"$1", :online, :_}
      :mnesia.select(Tracker, [{pattern, [], [:"$1"]}])
    end
    |> :mnesia.transaction()
    # unwraps {:atomics, result}
    |> elem(1)
    |> List.flatten()
  end

  #
  #
  #
  @doc """
  Gets roles hosted in the cluster by offline nodes. Provides list of roles - this list is **not** deduplicated.
  """
  @spec get_inactive_roles() :: list()
  def get_inactive_roles() do
    #
    fn ->
      #  [:node, :role, :role_num, :health, :last_change]
      pattern = {Tracker, :_, :"$1", :offline, :_}
      :mnesia.select(Tracker, [{pattern, [], [:"$1"]}])
    end
    |> :mnesia.transaction()
    # unwraps {:atomics, result}
    |> elem(1)
    |> List.flatten()
  end

  #
  #
  #
  @doc """
  Gets the count of roles held by each node.
  Provides a list of lists, where each nested list is data from a single record in mnesia.
  """
  def get_active_roles_by_host() do
    #
    fn ->
      #  [:node, :role, :role_num, :health, :last_change]
      pattern = {Tracker, :"$1", :"$2", :online, :_}
      :mnesia.select(Tracker, [{pattern, [], [:"$$"]}])
    end
    |> :mnesia.transaction()
    # unwraps {:atomics, result}
    |> elem(1)
  end

  #
  #
  # [{Tracker, ^node, :member, _health, _last_change}]
  @doc """
  Gets the roles hosted on a given host.
  """
  def is_host_running_role?(nodeName, role) do
    #
    [{Tracker, ^nodeName, host_roles, _health, _last_change}] =
      fn ->
        :mnesia.read({Tracker, nodeName})
      end
      |> :mnesia.transaction()
      # unwraps {:atomics, result}
      |> elem(1)

    # Check if role is present in list
    Enum.find(host_roles, &(&1 == role))
    #
  end

  #
  #
  #
  @doc """
  Checks if a role is hosted in the cluster. Does not return truthful if the hosting node is offline.
  """
  def is_role_hosted?(role) when is_atom(role) do
    f_role =
      get_active_roles()
      |> Enum.find(&(&1 == role))

    f_role != nil
  end

  #
  #
  @doc """
  Add role to a node.
  """
  @spec add_role(atom(), atom()) :: :ok
  def add_role(nodeName, role) do
    fn ->
      # ReadLock record
      [{Tracker, ^nodeName, host_roles, health, _last_change}] =
        :mnesia.wread({Tracker, nodeName})

      # add new role to existing roles
      :mnesia.write({Tracker, nodeName, [role | host_roles], health, DateTime.now!("Etc/UTC")})
    end
    |> :mnesia.transaction()
    |> elem(1)
  end

  #
  #
  @doc """
  Remove role from a node.
  """
  @spec remove_role(atom(), atom()) :: :ok
  def remove_role(nodeName, role) do
    fn ->
      # ReadLock record
      [{Tracker, ^nodeName, host_roles, health, _last_change}] =
        :mnesia.wread({Tracker, nodeName})

      # remove roles
      :mnesia.write(
        {Tracker, nodeName, List.delete(host_roles, role), health, DateTime.now!("Etc/UTC")}
      )
    end
    |> :mnesia.transaction()
    |> elem(1)
  end

  #
  #
  @doc """
  Clear all roles from a node.
  """
  @spec clear_roles(atom()) :: :ok
  def clear_roles(nodeName) do
    fn ->
      # ReadLock record
      [{Tracker, ^nodeName, _host_roles, health, _last_change}] =
        :mnesia.wread({Tracker, nodeName})

      # remove roles
      :mnesia.write({Tracker, nodeName, [], health, DateTime.now!("Etc/UTC")})
    end
    |> :mnesia.transaction()
    |> elem(1)
  end

  #
  #
  @doc """
  Clear all roles from offline nodes. Returns list of roles cleared.
  """
  @spec clear_offline_roles() :: list()
  def clear_offline_roles() do
    fn ->
      # Create Pattern to get offline nodes
      #
      pattern = {Tracker, :"$1", :"$2", :offline, :_}
      # produces list of lists
      :mnesia.select(Tracker, [{pattern, [], [:"$$"]}])
      # remove roles from nodes, returns list of roles
      |> clear_offline_roles([])
    end
    |> :mnesia.transaction()
    |> elem(1)
  end

  #
  # End loop
  defp clear_offline_roles([], out) do
    out
    |> List.flatten()
  end

  #
  # Working loop
  defp clear_offline_roles([[nodeName, roles] | records], out) do
    :mnesia.write({Tracker, nodeName, [], :offline, DateTime.now!("Etc/UTC")})
    clear_offline_roles(records, [roles | out])
  end

  #
  #
  #
  #
  @doc """
  Compares a list of roles to what is hosted in the Tracker.
  Returns roles that are not hosted in Mnesia, but provided in the argument.
  Duplicate inputs are allowed and encouraged.
  """
  @spec find_work(list()) :: list()
  def find_work(role_list) do
    # Roles being hosted + roles provided
    find_work(role_list, get_active_roles())
  end

  #
  # End loop
  defp find_work(role_list, []) do
    role_list
  end

  #
  # working loop
  defp find_work(role_list, [cluster_role_h | cluster_roles]) do
    role_list
    |> List.delete(cluster_role_h)
    # recurse
    |> find_work(cluster_roles)
  end

  #
  #
end
