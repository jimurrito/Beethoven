defmodule Beethoven.RoleMgmt.Failover do
  @moduledoc """
  Failover monitor for roles.
  Listens for updates from `Beethoven.CoreServer` and will reassign work on the `RoleMgmt.Assign.Tracker`.
  Will reassign using `Beethoven.Allocator`.
  The update to mnesia will be monitored by `Assign` who will handle the assignment to self.
  """

  alias Beethoven.RoleMgmt.Assign
  alias Beethoven.CoreServer
  alias Beethoven.RoleMgmt.Assign.Tracker, as: RoleTracker

  require Logger
  use GenServer
  use CoreServer

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # GenServer callback functions
  #

  #
  #
  @doc """
  Supervisor Entry point.
  """
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(init_args \\ []) do
    GenServer.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  #
  #
  @impl true
  def init(_init_arg) do
    # Get CoreServer updates
    :ok = alert_me()
    Logger.info(status: :startup_complete)
    {:ok, :ok}
  end

  #
  #
  @impl true
  def handle_cast({:node_update, {nodeName, status}}, :ok) do
    status
    |> case do
      :online ->
        {:noreply, :ok}

      :offline ->
        Logger.warning(operation: :node_down_reassign, node: nodeName)
        {:noreply, :ok, {:continue, {:reassign, nodeName}}}
    end
  end

  #
  #
  @impl true
  def handle_continue({:reassign, nodeName}, :ok) do
    #
    :ok =
      fn ->
        # Acquire locks
        _ = :mnesia.lock_table(RoleTracker, :read)
        _ = :mnesia.lock_table(RoleTracker, :write)
        # iterates all rows and removes the downed node.
        :mnesia.foldl(
          fn record, _acc -> check_and_reassign(record, nodeName) end,
          :ok,
          RoleTracker
        )
      end
      |> :mnesia.transaction()
      |> elem(1)

    #
    {:noreply, :ok}
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Public API functions
  #

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Internal functions
  #

  #
  #
  @doc """
  Removes a given node from a Assign.Tracker record and reassigns the role.
  """
  @spec check_and_reassign(Assign.record(), node()) :: Assign.record()
  def check_and_reassign(record, nodeName) do
    {RoleTracker, role, count, _assigned, workers, _last_changed} = record
    #
    # check if the node is even contained on the role.
    Enum.member?(workers, nodeName)
    |> case do
      # not a member, do not touch record
      false ->
        record

      # does match, prune and reassign
      true ->
        # remove the node
        pruned_workers = Enum.filter(workers, &(&1 != nodeName))
        # Pick new node from allocator list
        # Filtering out the nodes that already exist.
        [new_worker | _rest] =
          Beethoven.Allocator.allocation_list()
          |> Enum.filter(&(!Enum.member?(pruned_workers, &1)))

        # Add new node to worker list
        new_workers = [new_worker | pruned_workers]
        # return modified record
        {RoleTracker, role, count, length(new_workers), new_workers, DateTime.now!("Etc/UTC")}
    end
  end

  #
  #
end
