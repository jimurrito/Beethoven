defmodule Beethoven.HwMon do
  @moduledoc """
  Stack of services to help check system utilization and push sampled data into the `Beethoven.Allocator` stack of services.

  # Public API

  - `get_hw_usage/0` Dumps the entire hardware usage Mnesia table.

  # Readme

  This module contains 2 primary services:

  - `Server` This service will take samples of system performance and send the data to multiple services within Beethoven.
  The most current data is stored in an Mnesia table.
  - `Archive` Archive hosts historical performance signals.
  Will store up to 100k entries *per metric*. This is a hard limit. Older logs will be pruned in a FIFO manor.
  This data is stored in an ETS table on the local node.

  """

  require Logger
  use Supervisor

  alias __MODULE__, as: HwMon

  alias __MODULE__.Server, as: HwServer

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
  @spec get_hw_usage() :: [{module(), node(), float(), float(), DateTime.t()}]
  def get_hw_usage() do
    HwServer.fetch_all()
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
    Supervisor.start_link(__MODULE__, init_args, name: __MODULE__)
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
