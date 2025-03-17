defmodule Beethoven.Core do
  @moduledoc """
  Core of Coordinator service. This is the primary GenServer for the service.
  """

  use GenServer
  require Logger

  alias Beethoven.Ipv4
  alias Beethoven.Listener
  alias Beethoven.Tracker
  alias Beethoven.Locator

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
    #
    Logger.info("Starting Beethoven.")
    GenServer.cast(__MODULE__, {:start_seek, 1})
    {:ok, :seeking}
  end

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
    # attempt join on all nodes in list
    # stops at first response from a socket
    Locator.try_join_iter(hostIPs, 33000)
    |> case do
      # successfully joined Mnesia cluster => Cluster state => need to make ram copies
      :ok ->
        Logger.info("[start_seek] Seeking completed successfully.")
        GenServer.cast(__MODULE__, :to_clustered)
        {:noreply, :transitioning}

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
          # Cast to start standalone mode
          GenServer.cast(__MODULE__, :to_standalone)
          {:noreply, :transitioning}
        else
          # Retry
          # backoff in milliseconds
          backoff = :rand.uniform(20) * 100

          Logger.debug(
            "[start_seek] Retry backoff (#{backoff |> Integer.to_string()}) milliseconds."
          )

          # Sleep
          Process.sleep(backoff)
          # Cast seeking
          GenServer.cast(__MODULE__, {:start_seek, attemptNum + 1})
          {:noreply, :seeking}
        end
    end
  end

  #
  #
  # Triggers clustering mode
  @impl true
  def handle_cast(:to_clustered, :transitioning) do
    Logger.info("[to_clustered] Entering ':clustered' mode.")

    Listener.start_link([])
    |> case do
      {:ok, pid} ->
        # Starts monitoring of Socket Server
        _ref = Process.monitor(pid)
        # Start monitoring all nodes
        GenServer.cast(__MODULE__, :mon_all_node)
        #
        {:noreply, {:clustered, pid}}

      {:error, error} ->
        {:noreply, {:clustered, {:listener_failed, error}}}
    end
  end

  #
  #
  # Triggers standalone mode
  @impl true
  def handle_cast(:to_standalone, :transitioning) do
    Logger.info("[to_standalone] Entering ':standalone' mode.")
    # Starts tracker Mnesia table
    _result = Tracker.start()

    # Starts listener
    Listener.start_link([])
    |> case do
      {:ok, pid} ->
        # Starts monitoring of Socket Server
        _ref = Process.monitor(pid)
        {:noreply, {:standalone, pid}}

      {:error, error} ->
        # Fail service as standalone server with no listener is pointless
        {:noreply, {:failed, {:standalone_listener_start_failure, error}}}
    end
  end

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
  # Converts a standalone coordinator to a clustered one.
  @impl true
  def handle_cast(:standalone_to_clustered, {:standalone, socket}) do
    Logger.info(
      "[standalone_to_clustered] Beethoven transitioned modes: [:standalone] => [:clustered]"
    )

    # GenServer.cast(__MODULE__, :mon_all_node)
    {:noreply, {:clustered, socket}}
  end

  #
  #
  # Converts a clustered coordinator to a standalone one (Socket is a PID)
  @impl true
  def handle_cast(:clustered_to_standalone, {:clustered, socket}) when is_pid(socket) do
    Logger.info("[clustered_to_standalone]  transitioned modes: [:clustered] => [:standalone]")
    {:noreply, {:standalone, socket}}
  end

  #
  # Converts a clustered coordinator to a standalone one, but the socket is shutdown
  # :clustered_to_standalone, {:clustered, {:listener_failed, :shutdown}}
  @impl true
  def handle_cast(:clustered_to_standalone, {:clustered, {:listener_failed, _error}}) do
    Logger.info(
      "[clustered_to_standalone] Beethoven transitioning modes: [:clustered] => [:standalone]"
    )

    GenServer.cast(__MODULE__, :to_standalone)
    {:noreply, :transitioning}
  end

  #
  #
  #
  #
  # Converts a clustered coordinator to a standalone one (Socket is a PID)
  @impl true
  def handle_cast(:start_role_server, state) do
    Logger.info("Starting RoleServer.")
    # Check if alive already
    Process.whereis(RoleServer)
    |> Process.alive?()
    |> if do
      Logger.debug("RoleServer is already running. Nothing to do.")
    else
      _pid_data = Process.spawn(RoleServer, [:monitor])
    end

    {:noreply, state}
  end

  #
  #
  # Converts a clustered coordinator to a standalone one (Socket is a PID)
  @impl true
  def handle_cast(:stop_role_server, state) do
    Logger.info("Stopping RoleServer.")
    # Check if alive already
    pid = Process.whereis(RoleServer)

    pid
    |> Process.alive?()
    |> if do
      Process.exit(pid, "#{__MODULE__}")
    else
      Logger.debug("RoleServer is already stopped. Nothing to do.")
    end

    {:noreply, state}
  end

  #
  #
  #
  #
  #
  #
  # Triggers coping mnesia table to memory
  @impl true
  def handle_call({:make_copy, table}, _from, {:clustered, socket}) do
    Tracker.copy_table(table)
    |> case do
      # copy was successful or already existed
      :ok -> {:noreply, {:clustered, socket}}
      # Copy failed => coordinator goes into failed state.
      {:error, _error} -> {:reply, {:failed, :copy_failed}}
    end
  end

  #
  #
  # gets coordinator mode - when existing mode is not a tuple
  # ONLY CALLED EXTERNALLY
  @impl true
  def handle_call(:get_mode, _from, {mode, socket}) do
    {:reply, mode, {mode, socket}}
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
  # Used to handle PID monitoring messages.
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, :shutdown}, {mode, socket}) when pid == socket do
    Logger.critical("[listener_down] Beethoven Listener service has shutdown.")
    {:noreply, {mode, {:listener_failed, :shutdown}}}
  end

  #
  #
  # Used to handle :nodedown monitoring messages.
  @impl true
  def handle_info({:nodedown, nodeName}, state) when is_atom(nodeName) do
    Logger.warning("[nodedown] Node (#{nodeName}) has gone offline.")

    # Job to handle state change for the node - avoids holding genserver
    job = fn ->
      # backoff in milliseconds (random number between 10-19 seconds)
      backoff = (:rand.uniform(10) + 9) * 1_000

      Logger.debug(
        "[nodedown] Backing off for #{(backoff / 1_000) |> Float.to_string()} seconds prior to moving node (#{nodeName}) to failed state in the table."
      )

      Process.sleep(backoff)

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
