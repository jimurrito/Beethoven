defmodule Beethoven.Substrate do
  @moduledoc """
  Supervisor for core services.
  These are the services that need to start once Locator has determined the cluster state.

  # Nested services:
  - `Beethoven.Allocator` Stack of services to track and aggregate signals to determine how busy a node is.
  - `Beethoven.HwMon` Hardware monitor stack. Tracks hardware resource consumption and both stores the data historically and sends signals to `Allocator`.
  - `Beethoven.CoreServer` Node monitoring service. Can send signals to callers when node state changes.
  - `Beethoven.BeaconServer` TCP server for Beethoven instances to find each other. This interacts with the `Locator` service on other nodes.
  - `Beethoven.RoleServer` Role management and allocation service that can host roles defined in config.ex.
  """

  require Logger
  use Supervisor

  #
  #
  @doc """
  Supervisor Entry point.
  """
  @spec start_link(mode: :clustered | :standalone) :: GenServer.on_start()
  def start_link(init_args \\ []) do
    Supervisor.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  #
  #
  @impl true
  def init(mode: mode) do
    children = [
      # Allocator
      Beethoven.Allocator,
      # Hardware monitor
      Beethoven.HwMon,
      # Core Server
      {Beethoven.CoreServer, mode},
      # Beacon server
      Beethoven.BeaconServer,
      # Role Server
      #Beethoven.RoleServer
      # New role server
      Beethoven.RoleMgmt
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  #
  #
end
