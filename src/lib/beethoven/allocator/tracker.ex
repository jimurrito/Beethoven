defmodule Beethoven.Allocator.Tracker do
  @moduledoc """
  Allocator service to aggregate how busy nodes are within the cluster.
  Utilizes `Beethoven.AllocAgent` behaviour to egress data into the allocator.
  """
  alias Beethoven.CoreServer
  alias Beethoven.DistrServer
  alias __MODULE__, as: AllocTracker

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
  def start_link(init_args \\ []) do
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
  #
end
