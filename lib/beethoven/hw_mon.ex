defmodule Beethoven.HwMon do
  @moduledoc """
  Supervisor for the HwMon stack of PIDs.
  These PIDs log historical hardware consumption and signal changes to `Beethoven.Allocator.Ingress`.
  """

  require Logger
  use Supervisor

  alias __MODULE__.Supervisor, as: HwMonSup
  alias __MODULE__, as: HwMon

  alias __MODULE__.Server.Tracker, as: HwTracker

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Public API functions
  #

  #
  #
  @doc """
  Get Node performance specs from Mnesia.

      {Beethoven.HwMon.Server.Tracker, :node, :avail_cpu, :avail_ram_gb, :last_change}
  """
  @spec get_hw_usage() :: [{:mnesia.table(), node(), float(), float(), DateTime.t()}]
  def get_hw_usage() do
    :mnesia.dirty_select(HwTracker, [
      {:mnesia.table_info(HwTracker, :wild_pattern), [], [:"$_"]}
    ])
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Supervisor functions
  #

  #
  #
  @doc """
  Supervisor Entry point.
  """
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(init_args \\ []) do
    Supervisor.start_link(__MODULE__, init_args, name: HwMonSup)
  end

  #
  #
  @impl true
  def init(_init_arg) do
    children = [
      # HwMon Server
      HwMon.Server,
      # Archive server
      HwMon.Archive
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  #
  #
end
