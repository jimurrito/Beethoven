defmodule Beethoven.Core do
  @moduledoc """
  Core of Coordinator service. This is the primary GenServer for the service.
  """

  use GenServer
  require Logger

  alias __MODULE__.Lib.Cast, as: CastLib
  alias __MODULE__.Lib.MnesiaNotify, as: MNotify
  alias __MODULE__.Lib.Node, as: NodeLib
  alias __MODULE__.Client
  alias Beethoven.Utils
  alias Beethoven.Ipv4
  alias Beethoven.Listener
  alias Beethoven.Tracker
  alias Beethoven.Locator
  alias Beethoven.Role, as: RoleServer
  alias Beethoven.RootSupervisor, as: RS

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
  # Callback when server is started by another PID.
  # needs to return {:ok, state}
  @impl true
  def init(_args) do
    # Start Mnesia
    :ok = :mnesia.start()
    Logger.info("Starting Beethoven.")
    # Start Seeking job
    GenServer.cast(__MODULE__, {:start_seek, 1})
    {:ok, :seeking}
  end

  #
  #
  # Attempts recovery when Core Server is in failed state.
  @impl true
  def handle_cast(:recover, {:failed, _}) do
    # Calls Lib module
    {:noreply, CastLib.recover()}
  end

  #
  #
  # Triggers when Core Server is in failed state.
  @impl true
  def handle_cast(request, {:failed, msg}) do
    Logger.error(
      "[#{request}] Request '#{request}' was cast to the Beethoven, but it is in a failed state."
    )

    {:noreply, {:failed, msg}}
  end

  #
  #
  # Mode that handles the searching for other Beethoven instances and eventually decides the mode.
  @impl true
  def handle_cast({:start_seek, attemptNum}, :seeking) do
    {:noreply, CastLib.start_seek(attemptNum)}
  end

  #
  #
  # Converts a standalone coordinator to a clustered one.
  # Allows for additional logic for the transition.
  @impl true
  def handle_cast(:standalone_to_clustered, {:standalone, server_data}) do
    Logger.info("Beethoven transitioned modes: [:standalone] => [:clustered]")
    {:noreply, {:clustered, server_data}}
  end

  #
  #
  # Converts a clustered coordinator to a standalone one
  # When it does this, it ensures the Listener is enabled and initiates RoleServer :check action.
  @impl true
  def handle_cast(
        :clustered_to_standalone,
        {:clustered, %{listener: listener_pids, role: role_pids}}
      ) do
    Logger.info("Beethoven transitioned modes: [:clustered] => [:standalone]")
    GenServer.cast(__MODULE__, :restart_listener)
    GenServer.cast(__MODULE__, :start_role_server)
    {:noreply, {:standalone, %{listener: listener_pids, role: role_pids}}}
  end

  #
  #
  # Start servers in an initial state - Assumes servers are not running already.
  @impl true
  def handle_cast(:start_servers, state) when is_atom(state) do
    {:noreply, CastLib.start_servers(state)}
  end

  #
  #
  # Starts/Restarts just the Listener Server
  @impl true
  def handle_cast(:restart_listener, state) do
    {:noreply, CastLib.restart_listener(state)}
  end

  #
  #
  # Starts RoleServer if not. If Started, initiate :check action on RoleServer.
  @impl true
  def handle_cast(:start_role_server, state) do
    {:noreply, CastLib.start_role_server(state)}
  end

  #
  #
  # Start/Stop Monitoring a node
  @impl true
  def handle_cast({:mon_node, {op, nodeName}}, mode) when is_atom(nodeName) do
    :ok = CastLib.monitor_node(op, nodeName)
    {:noreply, mode}
  end

  #
  #
  # Starts Monitoring all nodes in cluster.
  @impl true
  def handle_cast(:mon_all_node, mode) do
    :ok = CastLib.monitor_all_nodes()
    {:noreply, mode}
  end

  #
  #
  #
  #
  #
  # Triggers coping mnesia table to memory
  @impl true
  def handle_call({:make_copy, table}, _from, {:clustered, server_data}) do
    Tracker.copy_table(table)
    |> case do
      # copy was successful or already existed
      :ok -> {:noreply, {:clustered, server_data}}
      # Copy failed => Core Server goes into failed state.
      {:error, _error} -> {:reply, {:failed, :copy_failed}}
    end
  end

  #
  #
  # gets Core Server mode - when existing mode is not a tuple
  @impl true
  def handle_call(:get_mode, _from, {mode, server_data}) do
    {:reply, mode, {mode, server_data}}
  end

  #
  #
  # gets Core Server mode - when existing mode is not a tuple
  @impl true
  def handle_call(:get_mode, _from, mode) do
    {:reply, mode, mode}
  end

  #
  #
  #
  #
  #
  # Used to handle PID monitoring messages. (Listener)
  @impl true
  def handle_info(
        {:DOWN, p_ref, :process, p_pid, :shutdown},
        {mode, %{listener: {pid, ref}, role: role_pids}}
      )
      when p_pid == pid and p_ref == ref do
    Logger.emergency("Beethoven Listener server has shutdown.")
    {:noreply, {mode, %{listener: :failed, role: role_pids}}}
  end

  #
  # Used to handle PID monitoring messages. (RoleServer)
  @impl true
  def handle_info(
        {:DOWN, p_ref, :process, p_pid, :shutdown},
        {mode, %{listener: _listener_pids, role: {pid, ref}}}
      )
      when p_pid == pid and p_ref == ref do
    Logger.alert("Beethoven RoleServer has shutdown.")
    {:noreply, {mode, {:failed, :role_server_failed}}}
  end

  #
  #
  # Handles :nodedown monitoring messages.
  @impl true
  def handle_info({:nodedown, nodeName}, state) when is_atom(nodeName) do
    # Job to handle state change for the node - avoids holding genserver
    {:ok, _pid} =
      fn ->
        _result = NodeLib.down(nodeName)
      end
      # Spawn thread to handle job.
      |> Task.start()

    {:noreply, state}
  end

  #
  #
  # Redirects all Mnesia subscription events into the Lib.MnesiaNotify module.
  @impl true
  def handle_info({:mnesia_table_event, msg}, state) do
    :ok = MNotify.run(msg)
    {:noreply, state}
  end

  #
  #
  #
  #
  #
  # Catch All handle_info
  # MUST BE AT BOTTOM OF MODULE FILE **WITHOUT THIS, COORDINATOR GENSERVER WILL CRASH ON UNMAPPED MSG!!**
  @impl true
  def handle_info(msg, state) do
    Logger.warning("Beethoven received an un-mapped message.")
    IO.inspect({:unmapped_msg, msg})
    {:noreply, state}
  end

  #
  #
end
