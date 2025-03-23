defmodule Beethoven.Core do
  @moduledoc """
  Core of Coordinator service. This is the primary GenServer for the service.
  """

  use GenServer
  require Logger

  alias Beethoven.Utils
  alias __MODULE__.Lib.Transition, as: TransLib
  alias __MODULE__.Lib.MnesiaNotify, as: MNotify
  alias __MODULE__.Lib.Node, as: NodeLib
  alias __MODULE__.Lib.Startup
  alias Beethoven.Listener
  alias Beethoven.Role, as: RoleServer
  alias Beethoven.Az
  alias Beethoven.Tracker

  #
  #
  @doc """
  Entrypoint for supervisors or other PIDs that are starting this service.
  """
  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  #
  #
  # Initializes the service
  @impl true
  def init(_args) do
    Logger.info("Starting Beethoven.")
    # Start Mnesia
    :ok = :mnesia.start()

    # Get metadata from IMDS (if possible)
    region = Az.get_AzRegion()
    Logger.info("Node operating in (#{region}).")

    mode =
      region
      # Start seeking process
      |> Startup.start_seeking()
      |> case do
        # If :clustered -> monitor all active nodes
        :clustered ->
          :ok = Utils.monitor_all_nodes(true)

          :clustered

        # anything else
        out ->
          out
      end

    # start Tracker
    m_result = Tracker.start()
    Logger.debug("Attempted to start Tracker. Result: (#{m_result}).")

    # Start servers
    # TCP Listener
    _ = Listener.start([])
    # Role Allocation Server
    # {:ok, _ra_pid} = RoleAlloc.start_link([])
    # Role manager
    {:ok, _ro_pid} = RoleServer.start_link([])

    {:ok, mode}
  end

  #
  #
  #
  @impl true
  def handle_call({:transition, new_mode}, _from, mode) do
    Logger.info("Transitioning server modes: [#{mode}] => [#{new_mode}]")
    result = TransLib.transition(mode, new_mode)
    {:reply, result, new_mode}
  end

  #
  #
  # gets Core Server mode
  @impl true
  def handle_call(:get_mode, _from, mode) do
    {:reply, mode, mode}
  end

  #
  #
  # Handles :nodedown monitoring messages.
  @impl true
  def handle_info({:nodedown, nodeName}, mode) when is_atom(nodeName) do
    # Job to handle state change for the node - avoids holding genserver
    {:ok, _pid} =
      fn ->
        _result = NodeLib.down(nodeName)
      end
      # Spawn thread to handle job.
      |> Task.start()

    {:noreply, mode}
  end

  #
  #
  # Redirects all Mnesia subscription events into the Lib.MnesiaNotify module.
  @impl true
  def handle_info({:mnesia_table_event, msg}, mode) do
    #Logger.warning("MNESIA EVENT")
    #IO.inspect({:event, msg})
    :ok = MNotify.run(msg)
    {:noreply, mode}
  end

  #
  #
  #
  #
  #
  # Catch All handle_info
  # MUST BE AT BOTTOM OF MODULE FILE **WITHOUT THIS, COORDINATOR GENSERVER WILL CRASH ON UNMAPPED MSG!!**
  @impl true
  def handle_info(msg, mode) do
    Logger.warning("Beethoven received an un-mapped message.")
    IO.inspect({:unmapped_msg, msg})
    {:noreply, mode}
  end

  #
  #
end
