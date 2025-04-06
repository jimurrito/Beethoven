defmodule Beethoven.Core do
  @moduledoc """
  Core of Coordinator service. This is the primary GenServer for the service.
  """

  use GenServer
  require Logger

  alias __MODULE__.Transition, as: TransLib
  alias __MODULE__.MnesiaNotify, as: MNotify
  alias __MODULE__.Node, as: NodeLib
  alias __MODULE__.Startup
  alias Beethoven.Az
  alias Beethoven.Tracker
  alias Beethoven.Utils

  #
  #
  @doc """
  Entry point for Supervisors. Links calling PID this this child pid.
  """
  @spec start_link(any()) :: {:ok, pid()}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  #
  #
  # Initializes the service.
  @impl true
  def init(_args) do
    Logger.info("Starting Beethoven.")

    # Start Mnesia
    :ok = :mnesia.start()

    # See if we are in Azure
    # Get metadata from IMDS (if possible)
    # if not, we will get :no_azure
    mode =
      Az.get_AzRegion()
      # Input either region atom or :no_azure
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
    Logger.debug("Attempted to start Tracker.", result: m_result)

    # Start servers
    GenServer.cast(__MODULE__, :start_servers)

    {:ok, mode}
  end

  #
  #
  # Start Servers.
  # Servers are started within tasks to avoid holding up the server.
  # Processes are added to the application root supervisor
  @impl true
  def handle_cast(:start_servers, mode) do
    :ok = TransLib.start_servers()
    {:noreply, mode}
  end

  #
  #
  # Called when other Beethoven services thing the core server should transition
  # Desired mode is provided in the call
  @impl true
  def handle_call({:transition, new_mode}, _from, mode) do
    result = TransLib.transition(mode, new_mode)
    {:reply, result, new_mode}
  end

  #
  #
  # gets Core Server mode
  # :clustered or :standalone
  @impl true
  def handle_call(:get_mode, _from, mode) do
    {:reply, mode, mode}
  end

  #
  #
  # Handles :nodedown monitoring messages.
  # Spawns in task supervisor to avoid blocking genserver
  @impl true
  def handle_info({:nodedown, nodeName}, mode) when is_atom(nodeName) do
    # Job to handle state change for the node - avoids holding genserver
    # Spawn thread to handle job.
    _ = Task.start(fn -> NodeLib.down(nodeName) end)
    {:noreply, mode}
  end

  #
  #
  # Redirects all Mnesia subscription events into the Lib.MnesiaNotify module.
  @impl true
  def handle_info({:mnesia_table_event, msg}, mode) do
    :ok = MNotify.run(msg)
    {:noreply, mode}
  end

  #
  #
end
