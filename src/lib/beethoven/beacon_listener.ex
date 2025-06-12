defmodule Beethoven.BeaconListener do
  @moduledoc """
  Allows for access to the Beacon server outside of using `Beethoven.Locator`.
  Under the hood, this is just a modified Locator Server with most the same code and logic.
  Should be used by external entities who want data from Beacon, but do not wish to join or run all of Beethoven.
  """

  alias Beethoven.Ipv4
  alias Beethoven.Utils
  alias Beethoven.SeekChat

  alias __MODULE__.Table, as: ListenerTable

  require Logger
  use GenServer

  #
  #
  @typedoc """
  State used by the Genserver
  """
  @type svr_state() :: {:ready | :not_ready, list(node()), {:seek, list(), port(), integer()}}

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Modified code from `Beethoven.Locator`
  #

  #
  #
  @doc """
  Supervisor Entry point.
  """
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(init_args \\ []) do
    GenServer.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  #
  #
  @impl true
  def init(_init_arg) do
    Logger.info(status: :startup)
    # Table for node data
    _ = :ets.new(ListenerTable, [:set, :public, :named_table])
    # Check if we should use Azure
    hostIPs = Ipv4.get_host_network_addresses()
    # get Listener port
    port = Utils.get_app_env(:listener_port, 33000)
    # Start seek process
    :ok = GenServer.cast(__MODULE__, :seek)
    #
    Logger.info(status: :startup_complete, port: port, host_ips_found: length(hostIPs))
    #
    # 3 => max attempts
    {:ok, {:not_ready, [], {:seek, hostIPs, port, 3}}}
  end

  #
  # Call to check if the service is ready -> is ready
  @impl true
  def handle_call(:ready?, _from, {:ready, nodes, seek_config}) do
    {:reply, true, {:ready, nodes, seek_config}}
  end

  #
  # Call to check if the service is ready -> is not ready
  @impl true
  def handle_call(:ready?, _from, state) do
    {:reply, false, state}
  end

  #
  #
  # Starts seeking operation within continue
  # Allows for the operation to continue in the backend.
  @impl true
  def handle_cast(:seek, state) do
    {_status, _nodes, {:seek, hostIPs, port, max}} = state
    Logger.info(status: :starting_seek, max_attempts: max, num_o_ips: length(hostIPs), port: port)

    {:noreply, state, {:continue, {:seek, hostIPs, 1, max}}}
  end

  #
  #
  # exit seeking loop -> Max attempts -> Start core
  @impl true
  def handle_continue({:seek, _hostIPs, att, max}, _state)
      when att > max do
    #
    Logger.warning(
      status: :out_of_attempts,
      attempt_num: att,
      max_attempts: max
    )

    {:noreply, :not_found}
  end

  #
  #
  # Out of IPs -> increment seeking loop attempts -> backoff -> try again
  @impl true
  def handle_continue({:seek, [], att, max}, state) do
    #
    {_status, _nodes, {:seek, hostIPs, _port, _max}} = state
    #
    Logger.debug(status: :not_found, attempts: att, max_attempts: max)
    # backoff bases on config
    {:ok, backoff} =
      Utils.get_app_env(:common_random_backoff, 150..300)
      |> Utils.random_backoff()

    Logger.debug(status: :not_found_backoff_complete, waited_ms: backoff)
    #
    {:noreply, state, {:continue, {:seek, hostIPs, att + 1, max}}}
  end

  #
  #
  # handles seeking loop
  @impl true
  def handle_continue({:seek, [hostIP | hostIPs_tail], att, max}, state) do
    #
    {_status, _nodes, {:seek, _hostIPs, port, _max}} = state
    # attempt connection to listener (250 millisecond timeout)
    result =
      :gen_tcp.connect(hostIP, port, [:binary, packet: 0, active: false], 250)
      |> case do
        # server was found at IP
        {:ok, server_socket} -> {:connect, server_socket}
        # No listener at IP
        _error -> {:seek, hostIPs_tail, att, max}
      end

    # Continue to next continue block
    {:noreply, state, {:continue, result}}
  end

  #
  #
  # Handles connection to the found listener.
  # Gets lists of nodes without joining.
  @impl true
  def handle_continue({:connect, server_socket}, state) do
    {status, _nodes, {:seek, hostIPs, port, max}} = state
    #
    Logger.info(operation: :check_attempt, socket: server_socket)
    # Create a message, then serializes it into a binary
    msg = SeekChat.new_msg(:watching, :check) |> SeekChat.encode()
    # Sends request to check to the beacon server
    :ok = :gen_tcp.send(server_socket, msg)
    # get payload response from server
    {:ok, response} = :gen_tcp.recv(server_socket, 0)
    # Close socket
    :ok = :gen_tcp.close(server_socket)
    # Deserialize response
    %{sender: sender, type: :reply, payload: nodes} = response |> SeekChat.decode()
    #
    # handle response
    if is_list(nodes) do
      # payload is a list
      Logger.info(result: :check_successful, sender: sender, nodes: length(nodes))
      #
      {:noreply, {status, nodes, {:seek, hostIPs, port, max}}, {:continue, {:write_ets, nodes}}}
    else
      # catch all
      Logger.alert(
        "Failed to call the Beethoven cluster! Check server side logs. I am the client."
      )

      {:noreply, :seek_failure}
    end

    #
    #
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # New code
  #

  #
  #
  # Writes data to Mnesia
  @impl true
  def handle_continue({:write_ets, nodes}, {_status, _nodes, seek_config}) do
    now! = DateTime.now!("Etc/UTC")

    nodes
    # Writes nodes to ETS
    |> Enum.each(&:ets.insert(ListenerTable, {&1, now!}))

    {:noreply, {:ready, nodes, seek_config}}
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Public API
  #

  #
  #
  @doc """
  Checks if `Beethoven.BeaconListener` is ready.
  """
  @spec ready?() :: boolean()
  def ready?() do
    GenServer.call(__MODULE__, :ready?)
  end

  #
  #
  @doc """
  Similar to `ready?/0` but will block until the service is ready.
  Defaults to 5_000 milliseconds.
  """
  @spec until_ready(integer()) :: :ok | :timeout
  def until_ready(timeout \\ 5_000) do
    until = DateTime.add(DateTime.now!("Etc/UTC"), timeout, :millisecond)
    until_ready(until, false)
  end

  # when state is false
  defp until_ready(until, false) do
    DateTime.after?(DateTime.now!("Etc/UTC"), until)
    |> if do
      # we have timed out
      :timeout
    else
      # not timed out yet
      # check and recurse
      until_ready(until, ready?())
    end
  end

  # when ready is true
  defp until_ready(_until, true) do
    :ok
  end

  #
  #
  @doc """
  Restarts seek in the event a node goes down or potentially a new one gets added.
  """
  def start_seek() do
  end

  #
  #
end
