defmodule Beethoven.Allocator do
  @moduledoc """
  Allocator is a stack of processes that facilitate the aggregation of telemetry signals
  to determine how busy a given `Beethoven` node is.

  # Public API

  - `allocate/0` Provides the URI of the least-busy node in the cluster.
  - `get_all/0` Dumps all records from the `#{__MODULE__}.Tracker` mnesia table.

  # Readme

  The busyness of nodes is determined via signals.
  A signal is defined via the `signal/1` macro in `#{__MODULE__}.Agent`

  ## Example

      defmodule HttpSignal do
        use #{__MODULE__}.Agent
        signal(name: :http_connections, weight: 10.0, type: :count)
      end


  This creates a function on compile time that is used to send the signal to the Allocator.

  ## Example for `:count` type signals

        # Increases the internal count by 1
        HttpSignal.increment_http_connections_count/0

        # Decreases the internal count by 1
        HttpSignal.decrement_http_connections_count/0

  # Signal types

  - `:count` -> Controls a counter for a given metric.
  Creates 2 functions. `increment_{:name}_count/0`
  - `:percent` -> Represents a percent value.
  Creates 1 function. `percent_{:name}/1`
  - `:pre_processed` -> Represents an abstract value.
  Creates 1 function. `pre_processed_{:name}/1`

  # Signal handling

  ## Ingress

  Once the signals are sent via the generated function, they are casted to a local instance of `#{__MODULE__}.Ingress`.
  This service will normalize the data from the function and save to ETS. Once saved, it will signal `#{__MODULE__}.Cruncher` to check the new data.

  ## Cruncher

  Once signaled, this service will call the ETS table shared with `#{__MODULE__}.Ingress` and grab all the current signal data.
  Using the weight and data payload for the signal, a busy score is generated. This score is stored in an Mnesia table for all other nodes to access.
  This flow allows other PIDs to call the public API for `#{__MODULE__}` and get the nodeURI for the node with the least amount of work on it.

  """

  require Logger
  alias Beethoven.DistrServer
  alias Beethoven.CoreServer
  alias __MODULE__.Supervisor, as: AllocSupervisor

  require Logger
  use DistrServer, subscribe?: false
  use CoreServer

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
    # get node alert
    :ok = alert_me()
    Logger.info(status: :startup_complete)
    {:ok, :ok}
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
          fetch(nodeName)
          |> case do
            # not found
            [] -> :mnesia.dirty_write({get_table_name(), nodeName, 0.0, now!})
            # found == do nothing
            _ -> :ok
          end

        #
        :offline ->
          :mnesia.dirty_delete(get_table_name(), nodeName)
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
    # gets all the records from the table. they come sorted from least-to-most busy.
    {_, node, score, _} =
      get_all()
      # get only the first
      |> List.first()

    #
    Logger.debug(status: :allocation_requested, provided: node, score: score)
    #
    node
  end

  #
  #
  @doc """
  Gets all the records from the Allocator table, but returns only the URIs of the nodes..
  Records come pre-sorted from least-to-most busy.
  """
  @spec allocation_list() :: [node()]
  def allocation_list() do
    # get all and unwrap each element to just the node
    get_all()
    |> Enum.map(&elem(&1, 1))
  end

  #
  #
  @doc """
  Gets all the records from the Allocator table.
  Records come pre-sorted from least-to-most busy.
  """
  @spec get_all() :: list(tuple())
  def get_all() do
    fetch_all()
    # sort by score
    |> Enum.sort_by(&elem(&1, 2), :asc)
  end

  #
  #
end
