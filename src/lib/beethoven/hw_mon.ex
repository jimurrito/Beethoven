defmodule Beethoven.HwMon do
  @moduledoc """
  Supervisor for the HwMon stack of PIDs.
  These PIDs log historical hardware consumption and signal changes to `Beethoven.Allocator.Ingress`.
  """

  require Logger
  use Supervisor

  alias __MODULE__.Supervisor, as: HwMonSup
  alias __MODULE__, as: HwMon

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
