defmodule Beethoven.Allocator do
  @moduledoc """
  Allocator is a stack of processes that facilitate the aggregation of telemetry signals
  to determine how busy a given `Beethoven` node is.

  # Public API

  - `allocate/0` Provides the URI of the least-busy node in the cluster.

  The busyness of nodes is determined via signals.
  Refer to the documentation for `Beethoven.Allocator.Agent` for more information on creating signals.
  """

  require Logger
  alias Beethoven.DistrServer
  alias Beethoven.CoreServer
  alias __MODULE__.Tracker, as: AllocTracker
  alias __MODULE__.Supervisor, as: AllocSupervisor

  require Logger
  use DistrServer, subscribe?: false

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # DistrServer callback functions
  #

  #
  #
  @doc """
  Supervisor Entry point.
  """
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(init_args) do
    #
    children = [
      # Ingress server for signal. Sets signals to cruncher.
      __MODULE__.Ingress,
      # Cruncher to aggregate data and set a score for the current node.
      __MODULE__.Cruncher
    ]

    # Spawn Supervisor
    opts = [strategy: :one_for_one, name: AllocSupervisor]
    _ = Supervisor.start_link(children, opts)
    #
    # Start GenServer
    DistrServer.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  #
  #
  @impl true
  def config() do
    %{
      tableName: AllocTracker,
      columns: [:node, :score, :last_change],
      indexes: [],
      dataType: :set,
      copyType: :multi
    }
  end

  #
  #
  # Setup table with all the roles defined in `config.exs`
  @impl true
  def create_action({tableName, _columns, _indexes, _dataType, _copyType}) do
    # now!
    now! = DateTime.now!("Etc/UTC")
    #
    [node() | Node.list()]
    |> Enum.each(&:mnesia.dirty_write({tableName, &1, 0.0, now!}))
  end

  #
  #
  @impl true
  def entry_point(_var) do
    # get node alert
    :ok = CoreServer.alert_me(__MODULE__)
    Logger.info(status: :startup_complete)
    {:ok, :ok}
  end

  #
  # Called by CoreServer when a node changes state or gets added to the cluster
  @impl true
  def node_update(nodeName, status) do
    DistrServer.cast(__MODULE__, {:node_update, nodeName, status})
  end

  #
  #
  @impl true
  def handle_cast({:node_update, nodeName, status}, state) do
    # now!
    now! = DateTime.now!("Etc/UTC")
    #
    :ok =
      status
      |> case do
        #
        :online ->
          :mnesia.dirty_read(AllocTracker, nodeName)
          |> case do
            # not found
            [] -> :mnesia.dirty_write({AllocTracker, nodeName, 0.0, now!})
            # found == do nothing
            _ -> :ok
          end

        #
        :offline ->
          :mnesia.dirty_delete(AllocTracker, nodeName)
      end

    {:noreply, state}
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Public API functions
  #

  #
  #
  @doc """
  Provides the URI of the least-busy node in the cluster.
  Using this function has no side effects so discarding the output without using it will not cause issues.
  """
  @spec allocate() :: node()
  def allocate() do
    #
    # Get all records
    {AllocTracker, node, score, _} =
      :mnesia.dirty_select(AllocTracker, [
        {{:"$1", :"$2", :"$3", :"$4"}, [], [:"$_"]}
      ])
      # sort by score
      |> Enum.sort_by(&elem(&1, 2), :asc)
      # get only the first
      |> List.first()

    #
    Logger.debug(status: :allocation_requested, provided: node, score: score)
    #
    node
  end
end
