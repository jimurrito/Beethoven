defmodule Beethoven.Tracker do
  @moduledoc """
  Module to handle the `Beethoven.Tracker` mnesia table.
  This table is used by beethoven to track the state and roles of nodes within the cluster.
  """

  require Logger
  alias Beethoven.Utils

  #
  #
  #
  @doc """
  Starts `Beethoven.Tracker` Mnesia table
  """
  @spec start() :: :ok | :copied | :already_exists
  def start() do
    #
    # checks if table already exists in the cluster
    if Utils.mnesia_table_exists?(__MODULE__) do
      # table already exists.
      # add ram copy
      Utils.copy_mnesia_table(__MODULE__)
      |> case do
        # Copy was successful
        :ok -> :copied
        # Table already exists in memory
        # if joined node power-cycled, this response is expected
        :already_exists -> :already_exists
        # bubble up rest
        e -> e
      end
    else
      Logger.debug("Creating 'Beethoven.Tracker' mnesia table.")

      :mnesia.create_table(__MODULE__,
        # Table schema
        attributes: [:node, :role, :health, :last_change],
        # Sets ram copies for ALL existing nodes in the cluster.
        ram_copies: [node() | Node.list()],
        # This setting orders the table by order the nodes joined the cluster.
        type: :ordered_set
      )

      # Create indexes - speeds up searches for data that does not regularly change
      Logger.debug("Creating Indexes in 'Beethoven.Tracker'")
      :mnesia.add_table_index(__MODULE__, :node)
      # Add self to tracker
      :ok = add_self()
      # Subscribe to tracker changes
      {:ok, _node} = subscribe()
      #
      :ok
    end
  end

  #
  #
  #
  @doc """
  Joins the `Beethoven.Tracker` mnesia table as a cluster node.
  """
  @spec join() :: :ok | :not_started | :copy_error
  def join() do
    if not Utils.mnesia_table_exists?(__MODULE__) do
      # Mnesia tracker table not started - nothing to join
      :not_started
    else
      # tracker table running
      # Add self to tracker
      :ok = add_self()
      # Copy table to local memory
      Utils.copy_mnesia_table(__MODULE__)
      |> case do
        # Failed to copy to memory
        # ignore failure as called fn has its own error logging
        {:error, error} ->
          Logger.emergency("Failed to copy mnesia table to memory! Error: #{error}")
          :copy_error

        # Copied table to memory or its already there
        _ ->
          # Subscribe to tracker changes
          {:ok, _node} = subscribe()
          #
          :ok
      end
    end
  end

  #
  #
  #
  @doc """
  Adds self to BeethovenTracking Mnesia table.
  Uses a record like this:

  `
  {Tracker, node(), roles, :online, DateTime.now!("Etc/UTC")}
  `
  """
  @spec add_self(list()) :: :ok
  def add_self(roles \\ []) do
    # Add self to tracker
    Logger.debug("Adding self to 'Beethoven.Tracker' Mnesia table.")

    {:atomic, :ok} =
      :mnesia.transaction(fn ->
        #  [:node, :role, :role_num, :health, :last_change]
        :mnesia.write({__MODULE__, node(), roles, :online, DateTime.now!("Etc/UTC")})
      end)

    :ok
  end

  #
  #
  #
  @doc """
  Subscribe to changes to the BeethovenTracking Mnesia table.
  """
  @spec subscribe() :: {:ok, node()} | {:error, reason :: term()}
  def subscribe() do
    # Subscribe to tracking table
    # :detailed is used to get the previous version of the record.
    :mnesia.subscribe({:table, __MODULE__, :detailed})
  end

  #
  #
  #
  @doc """
  List of builtin roles used for filtering.
  """
  @spec builtin_roles() :: list()
  def builtin_roles() do
    [:been_alloc]
  end

  #
  #
  #
  @doc """
  Removes builtin roles from a list of roles provided to the function.
  """
  @spec remove_builtins(list()) :: list()
  def remove_builtins(role_list) do
    role_list
    # Enumerates the provided list.
    # truthful returns from the fun are kept in the list.
    |> Enum.filter(
      # Checks if role is built in
      &(Enum.find(
          builtin_roles(),
          fn bir -> bir == &1 end
          # ensures built-ins are filtered out and others are kept.
        ) == nil)
    )
  end

  #
  #
  #
  @doc """
  Gets roles hosted in the cluster. Provides list of roles - this list is **not** deduplicated.
  """
  @spec get_active_roles() :: list()
  def get_active_roles() do
    # create anon for transaction
    fn ->
      #  [:node, :role, :role_num, :health, :last_change]
      # Only gets node names from records where the node is online.
      pattern = {__MODULE__, :_, :"$1", :online, :_}
      :mnesia.select(__MODULE__, [{pattern, [], [:"$1"]}])
    end
    |> :mnesia.transaction()
    # unwraps {:atomics, result}
    |> elem(1)
    # Flatten is used as :mnesia.select returns a list of lists.
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
      pattern = {__MODULE__, :_, :"$1", :offline, :_}
      :mnesia.select(__MODULE__, [{pattern, [], [:"$1"]}])
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
  @spec get_active_roles_by_host() :: list()
  def get_active_roles_by_host() do
    #
    fn ->
      #  [:node, :role, :role_num, :health, :last_change]
      pattern = {__MODULE__, :"$1", :"$2", :online, :_}
      :mnesia.select(__MODULE__, [{pattern, [], [:"$$"]}])
    end
    |> :mnesia.transaction()
    # unwraps {:atomics, result}
    |> elem(1)
  end

  #
  #
  #
  @doc """
  Checks if a role is hosted on a given node.
  """
  @spec is_host_running_role?(atom(), atom()) :: boolean()
  def is_host_running_role?(nodeName, role) when is_atom(nodeName) and is_atom(role) do
    #
    [{__MODULE__, ^nodeName, host_roles, _health, _last_change}] =
      fn ->
        :mnesia.read({__MODULE__, nodeName})
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
  Checks if a role is hosted in the cluster.
  Does not return truthful if the hosting node is offline.
  """
  @spec is_role_hosted?(atom()) :: boolean()
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
  def add_role(nodeName, role) when is_atom(nodeName) and is_atom(role) do
    fn ->
      # ReadLock record
      [{__MODULE__, ^nodeName, host_roles, health, _last_change}] =
        :mnesia.wread({__MODULE__, nodeName})

      # add new role to existing roles
      :mnesia.write({__MODULE__, nodeName, [role | host_roles], health, DateTime.now!("Etc/UTC")})
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
  def remove_role(nodeName, role) when is_atom(nodeName) and is_atom(role) do
    fn ->
      # ReadLock record
      [{__MODULE__, ^nodeName, host_roles, health, _last_change}] =
        :mnesia.wread({__MODULE__, nodeName})

      # remove roles
      :mnesia.write(
        {__MODULE__, nodeName, List.delete(host_roles, role), health, DateTime.now!("Etc/UTC")}
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
  def clear_roles(nodeName) when is_atom(nodeName) do
    fn ->
      # ReadLock record
      [{__MODULE__, ^nodeName, _host_roles, health, _last_change}] =
        :mnesia.wread({__MODULE__, nodeName})

      # remove roles
      :mnesia.write({__MODULE__, nodeName, [], health, DateTime.now!("Etc/UTC")})
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
      pattern = {__MODULE__, :"$1", :"$2", :offline, :_}
      # produces list of lists
      :mnesia.select(__MODULE__, [{pattern, [], [:"$$"]}])
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
    :mnesia.write({__MODULE__, nodeName, [], :offline, DateTime.now!("Etc/UTC")})
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
