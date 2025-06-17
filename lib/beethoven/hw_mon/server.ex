defmodule Beethoven.HwMon.Server do
  @moduledoc """
  DistrServer to monitor hardware resources and sends signals to `Beethoven.Allocator` plus the integrated Mnesia table.
  """

  alias Beethoven.DistrServer
  alias Beethoven.HwMon.Archive, as: HwArchive

  require Logger
  use DistrServer, subscribe?: false

  import Beethoven.HwMon.Signals

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
      tableName: HwMonTracker,
      columns: [:node, :avail_cpu, :core_count, :avail_ram_mb, :total_ram_mb, :last_change],
      indexes: [],
      # :mnesia data types
      dataType: :set,
      # :local | :multi
      copyType: :multi
    }
  end

  #
  #
  # Setup table with all the roles defined in `config.exs`
  @impl true
  def create_action({tableName, _columns, _indexes, _dataType, _copyType}) do
    now! = DateTime.now!("Etc/UTC")

    fn ->
      [node() | Node.list()]
      |> Enum.each(&:mnesia.write({tableName, &1, 0.0, 0.0, 0.0, 0.0, now!}))
    end
    |> :mnesia.transaction()
    |> elem(1)
  end

  #
  #
  @impl true
  def entry_point(_var) do
    :ok = GenServer.cast(__MODULE__, :check)
    Logger.info(status: :startup_complete)
    {:ok, :ok}
  end

  @doc """
    #
  # PERCENTAGE FORMAT
  #
  # YES -> 4% => 4.0 | 61% => 61.0
  # NO  -> 4% => 0.04 | 61% => 0.61
  """
  #
  @impl true
  def handle_cast(:check, state) do
    # get RAM amount
    {ram_percent, avail_ram, total_ram} = memory_usage()
    # get cpu
    {cpu_percent, num_cores} = cpu_usage()
    avail_cpu = num_cores * 100 - cpu_percent
    adjusted_cpu = cpu_percent / (num_cores * 100) * 100
    #
    #
    # Send Signal to Allocator
    :ok = percent_ram(ram_percent)
    # This accounts for many CPU Cores.
    :ok = percent_cpu(adjusted_cpu)

    #
    # Send signal to Archive
    :ok = HwArchive.cast_ram(ram_percent)
    :ok = HwArchive.cast_cpu(adjusted_cpu)
    #
    #
    # Update Mnesia
    :ok =
      :mnesia.dirty_write(
        {get_table_name(), node(), avail_cpu, num_cores, avail_ram, total_ram,
         DateTime.now!("Etc/UTC")}
      )

    #
    :ok = GenServer.cast(__MODULE__, :wait)
    {:noreply, state}
  end

  #
  @impl true
  def handle_cast(:wait, state) do
    # wait 30s
    :ok = Process.sleep(30_000)
    :ok = GenServer.cast(__MODULE__, :check)
    {:noreply, state}
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Internal functions
  #

  #
  # PERCENTAGE FORMAT
  #
  # YES -> 4% => 4.0 | 61% => 61.0
  # NO  -> 4% => 0.04 | 61% => 0.61

  #
  #
  @spec memory_usage() :: {float(), float(), float()}
  defp memory_usage() do
    [
      system_total_memory: system_total_memory,
      free_memory: _free_memory,
      total_memory: total_memory,
      buffered_memory: _buffered_memory,
      cached_memory: _cached_memory,
      total_swap: _total_swap,
      free_swap: _free_swap,
      available_memory: available_memory
    ] = :memsup.get_system_memory_data()

    # get memory used via total - available
    # then divide by system_total_memory to get the %
    percent = (system_total_memory - available_memory) / system_total_memory
    avail_in_mb = available_memory / 1_000_000
    total_in_mb = total_memory / 1_000_000
    {percent * 100, avail_in_mb, total_in_mb}
  end

  #
  #
  @spec cpu_usage() :: {float(), integer()}
  defp cpu_usage() do
    {cpu_list, _stats, _idles, _} = :cpu_sup.util([:detailed])
    # get # of cores
    cpu_num = length(cpu_list)
    # must divide by 256 as that represents 1% CPU usage.
    # then divide by the num of CPU cores.
    {:cpu_sup.avg5() / 256, cpu_num}
  end

  #
  #
end
