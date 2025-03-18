defmodule Beethoven.Core do
  @moduledoc """
  Core of Coordinator service. This is the primary GenServer for the service.
  """

  use GenServer
  require Logger

  alias Beethoven.Utils
  alias Beethoven.Ipv4
  alias Beethoven.Listener
  alias Beethoven.Tracker
  alias Beethoven.Locator
  alias Beethoven.Role, as: RoleServer
  alias Beethoven.RootSupervisor, as: RS

  @doc """
  Entrypoint for supervisors or other PIDs that are starting this service.
  """
  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  #
  #
  #
  #
  #
  #
  # Callback when server is started by another PID.
  # needs to return {:ok, state}
  @impl true
  def init(_args) do
    # Start Mnesia
    :ok = :mnesia.start()
    #
    Logger.info("Starting Beethoven.")
    GenServer.cast(__MODULE__, {:start_seek, 1})
    {:ok, :seeking}
  end

  #
  #
  #
  #
  #
  #
  #
  #
  # Attempts recovery when coordinator is in failed state.
  @impl true
  def handle_cast(:recover, {:failed, _}) do
    Logger.warning("[recover] Beethoven service recovery attempt initiated.")
    Logger.debug("[recover] Performing Stop/Start on Mnesia")
    :stopped = :mnesia.stop()
    :ok = :mnesia.start()
    # Start seeking
    GenServer.cast(__MODULE__, {:start_seek, 1})
    {:noreply, :seeking}
  end

  # Triggers when coordinator is in failed state.
  @impl true
  def handle_cast(request, {:failed, msg}) do
    Logger.error(
      "[#{request}] Request '#{request}' was cast to the Beethoven, but it is in a failed state."
    )

    {:noreply, {:failed, msg}}
  end

  # handles requests for the service to go into seeking state
  @impl true
  def handle_cast({:start_seek, attemptNum}, :seeking) do
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
        GenServer.cast(__MODULE__, :mon_all_node)
        GenServer.cast(__MODULE__, :start_servers)
        {:noreply, :clustered}

      # connected, but failed to join => Failed state
      :cluster_join_error ->
        Logger.error("[start_seek] Failed to join Mnesia Cluster. Check Server logs.")
        {:noreply, {:failed, :cluster_join_error}}

      # connected, but failed to join => Failed state
      # :copy_error ->
      #  Logger.error(
      #    "[start_seek] Failed to copy 'BeethovenTracker' table. Check Server logs."
      #  )
      #  {:noreply, {:failed, :copy_error}}

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
          GenServer.cast(__MODULE__, :start_servers)
          {:noreply, :standalone}
        else
          # Retry
          # backoff in milliseconds
          Utils.backoff(20, 0, 100)

          # Cast seeking
          GenServer.cast(__MODULE__, {:start_seek, attemptNum + 1})
          {:noreply, :seeking}
        end
    end
  end

  #
  #
  #
  #
  #
  #
  #
  # Start servers in an initial state - Assumes servers are not running already.
  @impl true
  def handle_cast(:start_servers, state) when is_atom(state) do
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
        {:noreply, {state, %{listener: listener, role: {role_pid, role_ref}}}}

      {:error, _error} ->
        # failed to start RoleServer. This is fatal!
        Logger.emergency(
          "Beethoven RoleServer failed to start. This Beethoven will now go into a failed state."
        )

        {:noreply, {:failed, :start_role_servers_failed}}
    end

    #
  end

  #
  #
  #
  #
  # %{listener: listener_pids, role: role_pids}
  @impl true
  def handle_cast(:restart_listener, {mode, %{listener: listener_pids, role: role_pids}}) do
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
            {:noreply, {mode, %{listener: {listener_pid, listener_ref}, role: role_pids}}}

          {:error, _error} ->
            Logger.error("Beethoven Listener failed to start. This is not a crash.")
            # failed to open socket
            {:noreply, {mode, %{listener: :failed, role: role_pids}}}
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
        {:noreply, {mode, %{listener: {pid, ref}, role: role_pids}}}
    end
  end

  #
  #
  #
  #
  # %{listener: listener_pids, role: role_pids}
  @impl true
  def handle_cast(:start_role_server, {mode, %{listener: listener_pids, role: {r_pid, r_ref}}}) do
    Process.alive?(r_pid)
    |> if do
      # PID alive => do nothing
      Logger.debug(
        "Role Server start was requested, but the server is already running. Doing nothing."
      )

      {:noreply, {mode, %{listener: listener_pids, role: {r_pid, r_ref}}}}
    else
      # Pid has failed - try and reboot
      Logger.info("Restarting RoleServer.")

      RoleServer.start_link([])
      |> case do
        {:ok, pid} ->
          ref = Process.monitor(pid)
          {:noreply, {mode, %{listener: listener_pids, role: {pid, ref}}}}

        {:error, _error} ->
          # failed to start RoleServer. This is fatal!
          Logger.critical(
            "Beethoven RoleServer failed to start. This Beethoven will now go into a failed state."
          )

          {:noreply, {:failed, :role_server_failed}}
      end
    end
  end

  #
  #
  #
  #
  #
  #
  #
  #
  # Start/Stop Monitoring a node
  @impl true
  def handle_cast({:mon_node, {op, nodeName}}, mode) when is_atom(nodeName) do
    case op do
      :start ->
        # Start monitoring a node
        Logger.info("[mon_node] Started monitoring Node (#{nodeName})")
        true = Node.monitor(nodeName, true)
        {:noreply, mode}

      :stop ->
        # Stop monitoring a node
        Logger.info("[mon_node] Stopped monitoring Node (#{nodeName})")
        true = Node.monitor(nodeName, false)
        {:noreply, mode}
    end
  end

  #
  #
  #
  #
  # Start Monitoring all nodes
  @impl true
  def handle_cast(:mon_all_node, mode) do
    nodes = Node.list()
    #
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

    #
    {:noreply, mode}
  end

  #
  #
  #
  #
  #
  #
  #
  #
  # Converts a standalone coordinator to a clustered one.
  @impl true
  def handle_cast(:standalone_to_clustered, {:standalone, server_data}) do
    Logger.info(
      "[standalone_to_clustered] Beethoven transitioned modes: [:standalone] => [:clustered]"
    )

    {:noreply, {:clustered, server_data}}
  end

  #
  #
  #
  #
  # Converts a clustered coordinator to a standalone one
  @impl true
  def handle_cast(
        :clustered_to_standalone,
        {:clustered, %{listener: listener_pids, role: role_pids}}
      ) do
    Logger.info("[clustered_to_standalone] transitioned modes: [:clustered] => [:standalone]")
    GenServer.cast(__MODULE__, :restart_listener)
    GenServer.cast(__MODULE__, :start_role_server)
    {:noreply, {:standalone, %{listener: listener_pids, role: role_pids}}}
  end

  #
  #
  #
  #
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
      # Copy failed => coordinator goes into failed state.
      {:error, _error} -> {:reply, {:failed, :copy_failed}}
    end
  end

  #
  #
  #
  #
  #
  #
  # gets coordinator mode - when existing mode is not a tuple
  # ONLY CALLED EXTERNALLY
  @impl true
  def handle_call(:get_mode, _from, {mode, server_data}) do
    {:reply, mode, {mode, server_data}}
  end

  #
  # gets coordinator mode - when existing mode is not a tuple
  # ONLY CALLED EXTERNALLY
  @impl true
  def handle_call(:get_mode, _from, mode) do
    {:reply, mode, mode}
  end

  #
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
    Logger.critical("[listener_down] Beethoven Listener service has shutdown.")
    {:noreply, {mode, %{listener: :failed, role: role_pids}}}
  end

  #
  #
  #
  # Used to handle PID monitoring messages. (RoleServer)
  @impl true
  def handle_info(
        {:DOWN, p_ref, :process, p_pid, :shutdown},
        {mode, %{listener: listener_pids, role: {pid, ref}}}
      )
      when p_pid == pid and p_ref == ref do
    Logger.critical("[roleserver_down] Beethoven RoleServer has shutdown.")
    {:noreply, {mode, %{listener: listener_pids, role: :failed}}}
  end

  #
  #
  #
  #
  #
  # Used to handle :nodedown monitoring messages.
  @impl true
  def handle_info({:nodedown, nodeName}, state) when is_atom(nodeName) do
    Logger.warning("[nodedown] Node (#{nodeName}) has gone offline.")

    # Job to handle state change for the node - avoids holding genserver
    job = fn ->
      # backoff in milliseconds (random number between 5-8.5 seconds)
      Utils.backoff(10, 9, 500)

      # attempt ping
      Node.ping(nodeName)
      |> case do
        # Server is backup -> re-enable monitoring
        :pong ->
          Logger.debug("[nodedown] Node (#{nodeName}) is back online.")

          GenServer.cast(__MODULE__, {:mon_node, {:start, nodeName}})
          :ok

        # Server is still unreachable -> attempt status change.
        :pang ->
          # update node state from :online to :offline
          {:atomic, :ok} =
            :mnesia.transaction(fn ->
              # See if the node still shows online
              :mnesia.read(BeethovenTracker, nodeName)
              |> case do
                # Node still marked as online on the table -> update
                [{BeethovenTracker, ^nodeName, _, :online, _}] ->
                  Logger.debug(
                    "[nodedown] Node (#{nodeName}) unreachable, but the status still shows :online. Updating state."
                  )

                  # Write updated state to table
                  :mnesia.write(
                    {BeethovenTracker, nodeName, :member, :offline, DateTime.now!("Etc/UTC")}
                  )

                  # Check if there are any other nodes
                  if length(Node.list()) == 0 do
                    # Standalone is now needed. All others are offline.
                    GenServer.cast(__MODULE__, :clustered_to_standalone)
                  end

                  :ok

                # Node still marked as offline or is already deleted -> do nothing
                _ ->
                  Logger.debug("[nodedown] Node (#{nodeName}) is already updated.")
                  :ok
              end
            end)
      end

      :ok
    end

    # Spawn thread to handle job.
    Task.start(job)

    #
    #
    # ADDITIONAL LOGIC FOR :nodedown SCENARIO
    #
    {:noreply, state}
  end

  #
  #
  # Used to handle new nodes added to the 'BeethovenTracker' table
  @impl true
  def handle_info(
        {:mnesia_table_event,
         {:write, BeethovenTracker, {BeethovenTracker, nodeName, :member, :online, _}, [],
          _pid_struct}},
        state
      ) do
    Logger.debug("[CoorTabEvt] Node (#{nodeName}) as been added to 'BeethovenTracker' table.")

    # Sending cast ensure we are monitoring the new node
    GenServer.cast(__MODULE__, {:mon_node, {:start, nodeName}})
    #
    # ADDITIONAL LOGIC FOR NEW NODES
    #
    {:noreply, state}
  end

  #
  #
  # Used to handle a node changing from online to offline 'BeethovenTracker' table
  @impl true
  def handle_info(
        {:mnesia_table_event,
         {:write, BeethovenTracker, {BeethovenTracker, nodeName, :member, :offline, _},
          [{BeethovenTracker, nodeName, :member, :online, _}], _pid_struct}},
        state
      ) do
    Logger.debug(
      "[CoorTabEvt] Node (#{nodeName}) has changed availability: [:online] => [:offline]."
    )

    # Sending cast ensure we stop monitoring the offline node
    GenServer.cast(__MODULE__, {:mon_node, {:stop, nodeName}})
    #
    {:noreply, state}
  end

  #
  #
  # Used to handle a node changing from offline to online 'BeethovenTracker' table
  @impl true
  def handle_info(
        {:mnesia_table_event,
         {:write, BeethovenTracker, {BeethovenTracker, nodeName, :member, :online, _},
          [{BeethovenTracker, nodeName, :member, :offline, _}], _pid_struct}},
        state
      ) do
    Logger.debug(
      "[CoorTabEvt] Node (#{nodeName}) has changed availability: [:offline] => [:online]."
    )

    # Sending cast ensure we start monitoring the offline node again
    GenServer.cast(__MODULE__, {:mon_node, {:start, nodeName}})
    #
    {:noreply, state}
  end

  #
  #
  # FILTERS NOISE FROM MNESIA TABLE EVENTS TO THE TRACKER!
  # MUST BE AT THE BOTTOM OF THE TRACKER EVENTS HANDLERS!
  @impl true
  def handle_info({:mnesia_table_event, _}, state) do
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
    Logger.warning("[unexpected] Beethoven received an un-mapped message.")
    IO.inspect({:unmapped_msg, msg})
    {:noreply, state}
  end

  #
  #
  #
end
