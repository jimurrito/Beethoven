defmodule Beethoven.HwMon.Archive do
  @moduledoc """
  Tracks historical CPU and RAM usage as sampled by `HwMon.Server`.
  """

  require Logger
  use GenServer

  alias __MODULE__.Table, as: ArchiveTable

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Types
  #

  #
  @typedoc """
  Stat categories.
  """
  @type stat_category() :: :cpu | :ram | :disk_io | :net_io

  #
  @typedoc """
  Stat object that is stored on ETS
  """
  @type stat_object() :: {stat_category(), list({DateTime.t(), float()})}

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
    Logger.info(status: :startup)
    _ = :ets.new(ArchiveTable, [:set, :public, :named_table])
    Logger.info(status: :startup_complete)
    {:ok, :ok}
  end

  #
  #
  @impl true
  def handle_cast({:ingest, {metric_type, timestamp, data}}, state) do
    #
    Logger.debug(operation: :ingest, metric_type: metric_type, data: data)
    #
    true =
      :ets.lookup(ArchiveTable, metric_type)
      |> case do
        # not found
        [] ->
          :ets.insert(ArchiveTable, {metric_type, [{timestamp, data}]})

        # found
        [{^metric_type, history}] ->
          :ets.insert(ArchiveTable, {metric_type, [{timestamp, data} | history]})
      end

    #
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
  Casts CPU telemetry to Archive.
  """
  @spec cast_cpu(float()) :: :ok
  def cast_cpu(data) do
    GenServer.cast(__MODULE__, {:ingest, {:cpu, DateTime.now!("Etc/UTC"), data}})
  end

  #
  #
  @doc """
  Casts RAM telemetry to Archive.
  """
  @spec cast_ram(float()) :: :ok
  def cast_ram(data) do
    GenServer.cast(__MODULE__, {:ingest, {:ram, DateTime.now!("Etc/UTC"), data}})
  end

  #
  #
  @doc """
  Casts DiskIO telemetry to Archive.
  """
  @spec cast_diskIO(float()) :: :ok
  def cast_diskIO(data) do
    GenServer.cast(__MODULE__, {:ingest, {:disk_io, DateTime.now!("Etc/UTC"), data}})
  end

  #
  #
  @doc """
  Casts networkIO telemetry to Archive.
  """
  @spec cast_networkIO(float()) :: :ok
  def cast_networkIO(data) do
    GenServer.cast(__MODULE__, {:ingest, {:net_io, DateTime.now!("Etc/UTC"), data}})
  end

  #
  #
  @doc """
  Gets telemetry for a given stat.
  """
  @spec get_stat(stat_category()) :: {:ok, stat_object()} | :not_found
  def get_stat(stat_name) do
    :ets.lookup(ArchiveTable, stat_name)
    |> case do
      [] -> :not_found
      [object] -> {:ok, object}
    end
  end

  #
  #
end
