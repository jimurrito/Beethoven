defmodule Beethoven.BeaconServer do
  @moduledoc """
  Beacon Server is used to help other Beethoven node find the cluster.
  This is the TCP Listener the `Beethoven.Locator` server will check for.

  ---

  # External API calls
  These are calls that can be made from external servers
  - `attempt_recover/0` -> casts a recover message to the Beacon server.
  Will restart the socket if in a failed state. Will do nothing otherwise.

  ---

  # Notes
  This TCP listener will communicate via the `Beethoven.SeekChat` module.
  This module provides tools and types for interacting over raw TCP packets between the Beacon server and Locator.
  """

  require Logger
  use GenServer
  alias Beethoven.CoreServer
  alias Beethoven.Utils
  alias Beethoven.BeaconTaskSupervisor, as: BTSup
  alias Beethoven.SeekChat

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
  @impl true
  def init(_init_arg) do
    #
    Logger.info(status: :startup)
    # Start Task manager for requests
    # Ignore results to let it fail if we are re-running init/1
    _result = Task.Supervisor.start_link(name: BTSup)
    #
    # pull port from env file. Default to 33000 otherwise
    listener_port = Utils.get_app_env(:listener_port, 33000)
    #
    Logger.info(status: :starting_socket, port: listener_port)
    #
    # Open Socket
    :gen_tcp.listen(
      listener_port,
      [:binary, active: false, reuseaddr: true]
    )
    |> case do
      #
      # successfully opened socket
      {:ok, socket} ->
        Logger.info(status: :startup_complete, port: listener_port)
        # Start accepting requests
        :ok = start_accept()
        {:ok, socket}

      #
      # Failed in anyway
      {:error, e} ->
        Logger.warning(status: :beacon_socket_failed, reason: e, port: listener_port)
        {:ok, {:error, e}}
    end
  end

  #
  #
  # Cast handler to restart the Server on request
  # this is only possible when the Beacon Server is in a failed state.
  @impl true
  def handle_cast(:recover, {:error, reason}) do
    Logger.warning(operation: :recover, previous_failure_reason: reason)
    # Run init/1 again
    {:ok, state} = init([])
    {:noreply, state}
  end

  #
  #
  # Cast handler to restart the Server on request
  # This handles the requests to recover when we are **not** failed.
  @impl true
  def handle_cast(:recover, socket) do
    {:noreply, socket}
  end

  #
  #
  # Catch all for any other messages when in a failed state.
  @impl true
  def handle_cast(msg, {:error, reason}) do
    Logger.alert(operation: :cast_while_failed, failure_reason: reason, message: msg)
    {:noreply, {:error, reason}}
  end

  #
  #
  # Starts accept loop
  # redirects to continue loop
  @impl true
  def handle_cast(:accept, socket) do
    Logger.info(operation: :start_accept)
    {:noreply, socket, {:continue, :accept}}
  end

  #
  #
  # Loop for accepting TCP requests
  @impl true
  def handle_continue(:accept, socket) do
    Logger.debug(operation: :awaiting_new_requests)
    # FIFO accept the request from the socket buffer.
    # This Fun is blocking until a request is received.
    {:ok, client_socket} = :gen_tcp.accept(socket)
    # Spawn worker to respond
    Logger.debug(operation: :spawning_worker, msg: "Locator request received.")
    :ok = spawn_worker(client_socket)
    # recurse
    {:noreply, socket, {:continue, :accept}}
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Client functions
  #

  #
  #
  @doc """
  Attempts a recovery operation on the Beacon Server.
  If Server is in a failed state, it will attempt to reboot it.
  If not, nothing will happen.

  Indication of the outcome will be found in the server logs for BeaconServer.
  """
  @spec attempt_recover() :: :ok
  def attempt_recover() do
    GenServer.cast(__MODULE__, :recover)
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Internal Lib functions
  #

  #
  #
  # Cast an accept loop to self
  @spec start_accept() :: :ok
  defp start_accept() do
    GenServer.cast(__MODULE__, :accept)
  end

  #
  #
  # Spawn child task to respond to caller
  @spec spawn_worker(:inet.socket()) :: :ok
  defp spawn_worker(client_socket) do
    # Spawn working thread to serve the response
    {:ok, pid} =
      Task.Supervisor.start_child(
        BTSup,
        # redirect request into a task PID
        fn -> :ok = serve(client_socket) end
      )

    # transfer ownership of the socket request to the worker PID
    # returns :ok to caller
    :gen_tcp.controlling_process(client_socket, pid)
  end

  #
  #
  # Fn to handle responding to the TCP caller
  @spec serve(:inet.socket()) :: :ok
  defp serve(client_socket) do
    Logger.debug(operation: :starting_worker)
    # Read data in socket
    {:ok, payload} = :gen_tcp.recv(client_socket, 0)
    # Decode into a SeekChat message
    %{sender: sender, type: type, payload: msgPayload} = SeekChat.decode(payload)
    # condition the output
    response =
      cond do
        # should ignore if we are the client for some reason
        sender == node() ->
          Logger.alert(result: :error, fail_reason: :phoned_self, sender: sender, msg: msgPayload)
          SeekChat.new_msg(:reply, :self)

        # Client performing Seeking request
        type == :seeking ->
          Logger.debug(operation: :client_seeking, sender: sender, msg: msgPayload)
          # Ping Node via Node modality
          Node.ping(sender)
          |> case do
            # Client is reachable
            # this means the name is correct, and node shares a secret cookie
            :pong ->
              Logger.debug(operation: :client_ping_success, sender: sender)
              # Call CoreServer and add a node to the cluster
              :ok = CoreServer.new_node(sender)
              SeekChat.new_msg(:reply, :joined)

            # Client is unreachable
            # either the name was incorrect and/or it did not share the same cookie.
            :pang ->
              Logger.debug(operation: :client_ping_failed, sender: sender)
              SeekChat.new_msg(:reply, :join_failed)
          end

        # Client performing a Watching request
        type == :watching ->
          Logger.debug(operation: :client_watching, sender: sender, msg: msgPayload)
          # return a list of nodes in the cluster
          SeekChat.new_msg(:reply, Node.list())

        # For some reason, client signed the message as :reply
        type == :reply ->
          Logger.alert(
            result: :error,
            fail_reason: :client_used_reply,
            sender: sender,
            msg: msgPayload
          )

          SeekChat.new_msg(:reply, :error)
      end

    #
    # Send response to caller
    # returns :ok
    :gen_tcp.send(client_socket, SeekChat.encode(response))
  end

  #
  #
end
