defmodule Beethoven.Alloc.Dispatch do
  @moduledoc """
  Allocator service to aggregate how busy nodes are within the cluster.
  Utilizes `Beethoven.AllocAgent` behaviour to egress data into the allocator.
  """
  alias Beethoven.DistrServer
  alias __MODULE__.Tracker, as: AllocTracker

  require Logger
  use DistrServer, subscribe?: true

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
      columns: [:node, :score, :telemetry, :last_change],
      indexes: [],
      dataType: :set,
      copyType: :multi
    }
  end

  #
  #
  # Setup table with all the roles defined in `config.exs`
  @impl true
  def create_action({_tableName, _columns, _indexes, _dataType, _copyType}) do
    :ok
  end

  #
  #
  @impl true
  def entry_point(_var) do
    Logger.info(status: :startup)
    #

    #
    Logger.info(status: :startup_complete)
    {:ok, :ok}
  end

  #
  #
end
