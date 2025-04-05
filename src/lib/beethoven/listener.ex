defmodule Beethoven.Listener do
  @moduledoc """
  Genserver/TCP listener used to help Beethoven instances find each other.
  """

  use GenServer
  require Logger
  alias Beethoven.Core, as: CoreServer

  #
  @doc """
  Entry point for Supervisors. Links calling PID this this child pid.
  """
  @spec start_link(any()) :: {:ok, pid()}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  #
  @doc """
  Entry point for Supervisors. Non-linking.
  """
  @spec start(any()) :: {:ok, pid()}
  def start(_args) do
    GenServer.start(__MODULE__, [], name: __MODULE__)
  end

  #
  # TODO!
  # FIX ALL THROW/RAISE CALLS IN THIS FUN
  #
  #
  # Callback for genserver start calls.
  @impl true
  def init(_args) do
    # Start Task manager for requests
    {:ok, task_pid} = Task.Supervisor.start_link(name: Beethoven.Listener.TaskSupervisor)
    # Create Monitor for the TaskSupervisor
    _ref = Process.monitor(task_pid)
    #
    # pull port from env file
    listener_port =
      Application.fetch_env(:beethoven, :listener_port)
      |> case do
        # port defined in config
        {:ok, port} ->
          port

        # port not defined
        :error ->
          Logger.notice(":listener_port not set in config/*.exs. Using default value '33000'.")
          33000
      end

    #
    port_string = Integer.to_string(listener_port)
    #
    # Open Socket
    socket =
      :gen_tcp.listen(
        listener_port,
        # :binary indicates the type of data we are expecting
        # active: false allows the genserver to respond manually to the TCP requests.
        # reuseaddr: true allows the socket to be reused if the PID dies.
        [:binary, active: false, reuseaddr: true]
      )
      |> case do
        #
        # successfully opened socket
        {:ok, socket} ->
          Logger.info("Now listening on port (#{port_string}).")
          #
          # Start accepting requests
          GenServer.cast(__MODULE__, :accept)
          socket

        #
        # Failed -> IP already in use
        {:error, :eaddrinuse} ->
          Logger.error(
            "Failed to bind listener socket to port [#{port_string}] as the port is already in-use. This is not an issue in ':clustered' mode."
          )

          #
          # Kill supervisor
          Process.whereis(Beethoven.Listener.TaskSupervisor)
          |> Process.exit("Beethoven.Listener -> :eaddrinuse | port: (#{port_string})")

          #
          throw(
            "Failed to bind listener socket to port [#{port_string}] as the port is already in-use. This is not an issue in ':clustered' mode."
          )

        #
        # Failed -> Unmapped
        {:error, _error} ->
          Logger.error(
            "Unexpected error occurred while binding listener socket to port [#{port_string}]."
          )

          #
          # Kill supervisor
          Process.whereis(Beethoven.Listener.TaskSupervisor)
          |> Process.exit("Beethoven.Listener -> :unexpected | port: (#{port_string})")

          #
          throw(
            "Unexpected error occurred while binding listener socket to port [#{port_string}]."
          )
      end

    #
    # return to caller
    {:ok, socket}
  end

  #
  #
  #
  # Starts accepting TCP requests.
  # Once received, a task is spawned to handle the request.
  @impl true
  def handle_cast(:accept, socket) do
    Logger.info("Listener now accepting requests.")
    #
    # Start accepting loop
    accept(socket)
    #
    # call back to self incase the accept recurse fails.
    :ok = GenServer.cast(self(), :accept)
    #
    # End cast
    {:noreply, socket}
  end

  #
  #
  #
  @doc """
  TCP accept loop.
  """
  @spec accept(any()) :: :ok
  def accept(socket) do
    # FIFO accept the request from the socket buffer.
    # This Fun is blocking until a request is received.
    {:ok, client_socket} = :gen_tcp.accept(socket)
    # Spawn working thread to serve the response
    {:ok, pid} =
      Task.Supervisor.start_child(
        Beethoven.Listener.TaskSupervisor,
        fn -> serve(client_socket) end
      )

    # transfer ownership of the socket request to the worker PID
    :ok = :gen_tcp.controlling_process(client_socket, pid)
    # Recurse
    accept(socket)
  end

  #
  #
  #
  # Fnc that runs in each request task.
  # handles logic for the client request and handles response.
  defp serve(client_socket) do
    #
    Logger.info("Beethoven received a coordination.")
    #
    # Read data in socket
    {:ok, payload} = :gen_tcp.recv(client_socket, 0)

    nodeName =
      payload
      # Remove \r\n from the payload (if present)
      |> String.replace("\r", "")
      |> String.replace("\n", "")
      # Convert to atom
      |> String.to_atom()

    Logger.debug("Node (#{nodeName}) has requested to join the Beethoven Cluster.")

    # test node asking to join
    case Node.ping(nodeName) do
      #
      # Failed to connect to node
      :pang ->
        Logger.error("Failed to ping node (#{nodeName}).")
        :gen_tcp.send(client_socket, "pang_error")

      #
      # Success -> connected to node
      :pong ->
        # add requester to Mnesia cluster
        :mnesia.change_config(:extra_db_nodes, [nodeName])
        |> case do
          #
          # Joined successfully.
          {:ok, _} ->
            Logger.info("Node (#{nodeName}) joined the Beethoven Cluster.")
            # Ensure Coordinator is in ':clustered' mode now
            _ = GenServer.call(CoreServer, {:transition, :clustered})
            # Send response to caller
            :gen_tcp.send(client_socket, "joined")

          #
          # Failed to join - merge_schema_failed
          {:error, {:merge_schema_failed, msg}} ->
            Logger.error(
              "Node (#{nodeName}) failed to join Beethoven cluster 'merge_schema_failed': '#{msg}' "
            )

            # Send response to caller
            :gen_tcp.send(client_socket, "merge_schema_failed")

          #
          # Failed - unexpected_error
          {:error, error} ->
            Logger.error(
              "Node (#{nodeName}) failed to join Beethoven cluster.",
              unexpected_error: error
            )

            # Send response to caller
            :gen_tcp.send(client_socket, "unexpected_error")
        end
    end
  end

  #
  #
  #
  #
  #
  #
  # Only PID it would be monitoring is the supervisor
  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, :shutdown}, socket) do
    Logger.critical("Beethoven.Listener's task Supervisor has shutdown.")
    {:noreply, socket}
  end

  #
  #
  #
  #
  #
  #
  # Catch All handle_info
  # MUST BE AT BOTTOM OF MODULE FILE **WITHOUT THIS, COORDINATOR GENSERVER WILL CRASH ON UNMAPPED MSG!!**
  @impl true
  def handle_info(msg, state) do
    Logger.warning("Beethoven.Listener received an un-mapped message.", unmapped_msg: msg)
    {:noreply, state}
  end
end
