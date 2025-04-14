defmodule Beethoven.Locator do
  @moduledoc """
  GenServer to handle searching for other Beethoven nodes or clusters.

  # Modes
  - `:seeking` -> Currently Searching for listening servers.
  - `:watching` ->  (TBD) Slower search to ensure there are no standalone clusters or nodes.

  ---

  # `:seeking`
  Service will start up and perform a seeking operation.
  The locator will start the Core service(s) once either is met:
  - (1). Seeking attempts have become exhausted. [CoreServer <- `:standalone`]
  - (2). A listener server is found. [CoreServer <- `:clustered`]

  > Core Services is defined as:
  > - `Beethoven.CoreServer`
  > - `Beethoven.RoleServer`
  > - `Beethoven.BeaconServer`

  ---

  # `:watching`
  Used when the cluster is in standalone mode.
  This mode will continue the scan for other clusters.
  This is needed to ensure there are no other clusters existing at the same time.
  """

  use GenServer
  require Logger
  alias Beethoven.Utils
  alias Beethoven.Ipv4
  alias Beethoven.SeekChat

  #
  # -TODO-
  # NEED TO ADD WATCHING MODES
  #
  #

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # GenServer callback functions
  #

  #
  #
  @doc """
  Entry point for a supervisor.
  """
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  #
  #
  # Callback for process start
  @impl true
  def init(_init_arg) do
    Logger.info(status: :startup)
    # Get list of hosts in defined IP range
    hostIPs = Ipv4.get_host_network_addresses()
    # get Listener port
    port = Utils.get_app_env(:listener_port, 33000)
    # Start seek process
    :ok = GenServer.cast(__MODULE__, :seek)
    #
    Logger.info(status: :startup_complete, port: port, host_ips_found: length(hostIPs))
    #
    # 3 => max attempts
    {:ok, {:seek, hostIPs, port, 3}}
  end

  #
  #
  # Starts seeking operation within continue
  # Allows for the operation to continue in the backend.
  @impl true
  def handle_cast(:seek, state) do
    {_mode, hostIPs, port, max} = state
    Logger.info(status: :starting_seek, max_attempts: max, num_o_ips: length(hostIPs), port: port)
    {:noreply, state, {:continue, {:seek, hostIPs, port, 1, max}}}
  end

  #
  #
  # exit seeking loop -> Max attempts -> Start core
  @impl true
  def handle_continue({:seek, _ips, _port, att, max}, {_mode, hostIPs, port, _max})
      when att > max do
    Logger.warning(status: :out_of_attempts, attempts: att, max_attempts: max)
    # Start Core in `:standalone` mode
    {:noreply, {:watching, hostIPs, port, max}, {:continue, {:start_core, :standalone}}}
  end

  #
  #
  # Out of IPs -> increment seeking loop attempts -> backoff -> try again
  @impl true
  def handle_continue({:seek, [], port, att, max}, state) do
    Logger.debug(status: :not_found, attempts: att, max_attempts: max)
    {_mode, hostIPs, _port, _max} = state
    # backoff (150 - 2250) Milliseconds
    :ok = Utils.backoff_n(__MODULE__, 15, 0, 150)
    #
    {:noreply, state, {:continue, {:seek, hostIPs, port, att + 1, max}}}
  end

  #
  #
  # handles seeking loop
  @impl true
  def handle_continue({:seek, [hostIP | hostIPs_tail], port, att, max}, state) do
    # attempt connection to listener (250 millisecond timeout)
    result =
      :gen_tcp.connect(hostIP, port, [:binary, packet: 0, active: false], 250)
      |> case do
        # server was found at IP
        {:ok, server_socket} -> {:connect, server_socket}
        # No listener at IP
        _error -> {:seek, hostIPs_tail, port, att, max}
      end

    # Continue to next continue block
    {:noreply, state, {:continue, result}}
  end

  #
  #
  # Handles connection to the found listener (in `:seek` mode).
  # Finishes connection to join cluster and moves to watching mode.
  @impl true
  def handle_continue({:connect, server_socket}, {:seek, hostIPs, port, max}) do
    Logger.info(operation: :connect_attempt)
    # Create a message, then serializes it into a binary
    msg = SeekChat.new_msg(:seeking, :join) |> SeekChat.encode()
    # Sends request to join to the listener server
    :ok = :gen_tcp.send(server_socket, msg)
    # get payload response from server
    {:ok, response} = :gen_tcp.recv(server_socket, 0)
    # Close socket
    :ok = :gen_tcp.close(server_socket)
    # Deserialize response
    %{sender: sender, type: :reply, payload: msgPayload} = response |> SeekChat.decode()
    # handle response
    cond do
      # The call is coming from.... inside the house!!
      sender == node() ->
        Logger.alert(result: :error, fail_reason: :phoned_self, sender: sender)
        raise("Somehow you phoned-home! This should never happen during :seeking phase.")

      # check msg contents
      msgPayload == :joined ->
        Logger.info(result: :joined, fail_reason: nil, sender: sender)

      # catch all
      true ->
        Logger.alert(
          "Failed to join the Beethoven cluster! Check server side logs. I am the client."
        )

        Logger.alert(result: :error, fail_reason: msgPayload, sender: sender)
        raise("Failed to join the Beethoven cluster! Check server side logs. I am the client.")
    end

    #
    {:noreply, {:watching, hostIPs, port, max}, {:continue, {:start_core, :clustered}}}
  end

  #
  #
  # Starts Core genserver under root Supervisor
  @impl true
  def handle_continue({:start_core, mode}, state) do
    # Start CoreServer under RootSupervisor
    Logger.info(operation: :started_core, mode: mode)
    {:ok, _pid} = Supervisor.start_child(Beethoven.RootSupervisor, {Beethoven.CoreServer, mode})

    #
    # Start RoleServer
    Logger.info(operation: :started_role_server)
    {:ok, _pid} = Supervisor.start_child(Beethoven.RootSupervisor, Beethoven.RoleServer)
    #
    {:noreply, state}
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Internal Lib functions
  #

  #
  #
end
