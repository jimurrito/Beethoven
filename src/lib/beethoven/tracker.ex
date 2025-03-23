defmodule Beethoven.Tracker do
  @moduledoc """
  State tracking for the Beethoven services. Uses Mnesia.
  Tabled named 'BeethovenTracker'
  """

  require Logger
  alias BeethovenTracker, as: Tracker
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
      Logger.debug("Creating 'BeethovenTracker' mnesia table.")

      :mnesia.create_table(Tracker,
        attributes: [:node, :role, :role_num, :health, :last_change],
        # Sets ram copies for ALL existing nodes in the cluster
        ram_copies: [node() | Node.list()],
        # This is so it works like a queue
        type: :ordered_set
      )

      # Create indexes - speeds up searches for data that does not regularly change
      Logger.debug("Creating Indexes in 'BeethovenTracker'")
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
    Logger.debug("Adding self to 'BeethovenTracker' Mnesia table.")

    {:atomic, :ok} =
      :mnesia.transaction(fn ->
        :mnesia.write({Tracker, node(), roles, 0, :online, DateTime.now!("Etc/UTC")})
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
  # https://elixirschool.com/en/lessons/storage/mnesia
  @doc """
  Gets roles hosted in the cluster
  """
  @spec get_active_roles() :: list()
  def get_active_roles() do
    #
    fn ->
      pattern = {Tracker, :_, :"$1", :_, :online, :_}
      :mnesia.select(Tracker, [{pattern, [], [:"$1"]}])
    end
    |> :mnesia.transaction()
    |> elem(1)
    |> List.flatten()
  end

  #
  #
  #
  @doc """
  Gets the count of roles held by each node.
  """
  def get_active_role_count() do
    #
    fn ->
      pattern = {Tracker, :"$1", :_, :"$2", :online, :_}
      :mnesia.select(Tracker, [{pattern, [], [:"$1", :"$2"]}])
    end
    |> :mnesia.transaction()
    |> elem(1)
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
