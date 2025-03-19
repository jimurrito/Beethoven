defmodule Beethoven.Core.Lib.Cast do
  @moduledoc """
  Library to reduce code length of Core server.
  Only handles casts to genserver
  """

  require Logger
  alias Beethoven.Core, as: CoreServer
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
  Attempts recovery of the CoreServer when in a failed state only.
  """
  @spec recover() :: :seeking
  def recover() do
    Logger.warning("[recover] Beethoven service recovery attempt initiated.")
    Logger.debug("[recover] Performing Stop/Start on Mnesia")
    :stopped = :mnesia.stop()
    :ok = :mnesia.start()
    # Start seeking - Recurse
    GenServer.cast(CoreServer, {:start_seek, 1})
    :seeking
  end

  #
  #
  @doc """
  Mode that handles the searching for other Beethoven instances and eventually decides the mode.
  """
  @spec start_seek(integer()) ::
          :clustered | :seeking | :standalone | {:failed, :cluster_join_error}
  def start_seek(attemptNum \\ 1) do
    Logger.info("[start_seek] Starting Seek attempt (#{attemptNum |> Integer.to_string()}).")
    # Get IPs in the host's network
    hostIPs = Ipv4.get_host_network_addresses()
    # get Listener port
    port =
      Application.fetch_env(:beethoven, :listener_port)
      |> case do
        {:ok, value} ->
          value

        :error ->
          Logger.notice(":listener_port is not set in config/*.exs. defaulting to (33000).")
          33000
      end

    # attempt join on all nodes in list
    # stops at first response from a socket
    Locator.try_join_iter(hostIPs, port)
    |> case do
      # successfully joined Mnesia cluster => Cluster state => need to make ram copies
      :ok ->
        Logger.info("[start_seek] Seeking completed successfully.")
        GenServer.cast(CoreServer, :mon_all_node)
        GenServer.cast(CoreServer, :start_servers)
        :clustered

      # connected, but failed to join => Failed state
      :cluster_join_error ->
        Logger.error("[start_seek] Failed to join Mnesia Cluster. Check Server logs.")
        {:failed, :cluster_join_error}

      # connected, but failed to join => Failed state
      # :copy_error ->
      #  Logger.error(
      #    "[start_seek] Failed to copy 'BeethovenTracker' table. Check Server logs."
      #  )
      #  {:failed, :copy_error}

      # No sockets listening in network => retry(x3) => Standalone
      :none_found ->
        Logger.info(
          "[start_seek] No sockets found on attempt (#{attemptNum |> Integer.to_string()})."
        )

        # If attempt is #3 fallback to standalone
        if attemptNum == 3 do
          # Standalone mode
          Logger.info("[start_seek] No nodes found. Defaulting to ':standalone' mode.")
          # Start Mnesia
          _ = Tracker.start()
          # Cast to start servers
          GenServer.cast(CoreServer, :start_servers)
          :standalone
        else
          # Retry
          # backoff in milliseconds
          Utils.backoff(20, 0, 100)

          # Cast seeking
          GenServer.cast(CoreServer, {:start_seek, attemptNum + 1})
          :seeking
        end
    end
  end

  #
  #
  @doc """
  Start servers in an initial state - Assumes servers are not running already.
  """
  @spec start_servers(any()) ::
          {atom(),
           :start_role_servers_failed
           | %{listener: :failed | {pid(), reference()}, role: {pid(), reference()}}}
  def start_servers(state) do
    #
    Logger.info("Starting Listener")

    # Supervisor.start_child(RS, Listener)
    listener =
      Listener.start([])
      |> case do
        {:ok, listener_pid} ->
          # {pid, ref}
          {listener_pid, Process.monitor(listener_pid)}

        {:error, _error} ->
          Logger.error("Beethoven Listener failed to start. This is not a crash.")
          # failed to open socket
          :failed
      end

    #
    Logger.info("Starting RoleServer")

    Supervisor.start_child(RS, RoleServer)
    |> case do
      {:ok, role_pid} ->
        role_ref = Process.monitor(role_pid)
        {state, %{listener: listener, role: {role_pid, role_ref}}}

      {:error, _error} ->
        # failed to start RoleServer. This is fatal!
        Logger.emergency(
          "Beethoven RoleServer failed to start. This Beethoven will now go into a failed state."
        )

        {:failed, :start_role_servers_failed}
    end
  end

  #
  #
  @doc """
  Starts/Restarts just the Listener Server
  """
  @spec restart_listener(
          {atom(),
           %{
             :listener => :failed | {pid(), reference()},
             :role => {pid(), reference()}
           }}
        ) ::
          {any(), %{listener: :failed | {pid(), reference()}, role: {pid(), reference()}}}
  def restart_listener({mode, %{listener: listener_pids, role: role_pids}}) do
    listener_pids
    |> case do
      # In failed state -> start
      :failed ->
        # Pid has failed - try and reboot
        Logger.info("Starting Listener.")

        Listener.start_link([])
        |> case do
          {:ok, listener_pid} ->
            listener_ref = Process.monitor(listener_pid)
            {mode, %{listener: {listener_pid, listener_ref}, role: role_pids}}

          {:error, _error} ->
            Logger.error("Beethoven Listener failed to start. This is not a crash.")
            # failed to open socket
            {mode, %{listener: :failed, role: role_pids}}
        end

      # data saved -> check and reboot
      {l_pid, l_ref} ->
        # PID alive => restart service
        Logger.info("Restarting Listener.")
        # Stop monitoring
        true = Process.demonitor(l_ref)
        # Kill process
        Process.exit(l_pid, "Beethoven.Core -> :restart_listener")
        # Start process
        {:ok, pid} = Listener.start_link([])
        # Monitor
        ref = Process.monitor(pid)
        #
        {mode, %{listener: {pid, ref}, role: role_pids}}
    end
  end

  #
  #
  @doc """
  Starts RoleServer if not. If Started, initiate :check action on RoleServer.
  """
  @spec start_role_server(
          {atom(), %{:listener => :failed | {pid(), reference()}, :role => {pid(), reference()}}}
        ) ::
          {atom(),
           :role_server_failed
           | %{listener: :failed | {pid(), reference()}, role: {pid(), reference()}}}
  def start_role_server({mode, %{listener: listener_pids, role: {r_pid, r_ref}}}) do
    Process.alive?(r_pid)
    |> if do
      # PID alive => do nothing
      Logger.debug(
        "Role Server start was requested, but the server is already running. Doing nothing."
      )

      # Tell role server to check roles
      GenServer.cast(RoleServer, :check)

      {mode, %{listener: listener_pids, role: {r_pid, r_ref}}}
    else
      # Pid has failed - try and reboot
      Logger.info("Restarting RoleServer.")

      RoleServer.start_link([])
      |> case do
        {:ok, pid} ->
          ref = Process.monitor(pid)
          {mode, %{listener: listener_pids, role: {pid, ref}}}

        {:error, _error} ->
          # failed to start RoleServer. This is fatal!
          Logger.critical(
            "Beethoven RoleServer failed to start. This Beethoven will now go into a failed state."
          )

          {:failed, :role_server_failed}
      end
    end
  end

  #
  #
  @doc """
  Start/Stop Monitoring a node.
  """
  @spec monitor_node(:start | :stop, atom()) :: :ok
  def monitor_node(operation, nodeName) do
    case operation do
      :start ->
        # Start monitoring a node
        Logger.info("[mon_node] Started monitoring Node (#{nodeName})")
        true = Node.monitor(nodeName, true)
        :ok

      :stop ->
        # Stop monitoring a node
        Logger.info("[mon_node] Stopped monitoring Node (#{nodeName})")
        true = Node.monitor(nodeName, false)
        :ok
    end
  end

  #
  #
  @doc """
  Starts Monitoring all nodes in cluster.
  """
  @spec monitor_all_nodes() :: :ok
  def monitor_all_nodes() do
    nodes = Node.list()

    Logger.debug(
      "[mon_all_node] Starting bulk monitoring on (#{length(nodes) |> Integer.to_string()}) nodes."
    )

    #
    nodes
    |> Enum.each(fn nodeName ->
      # Start monitoring the calling node
      Logger.info("[mon_all_node] Started monitoring Node (#{nodeName})")
      true = Node.monitor(nodeName, true)
    end)

    :ok
  end

  #
  #
end
