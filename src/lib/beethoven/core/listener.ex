defmodule Beethoven.Core.Listener do
  @moduledoc """
  Genserver/TCP listener used to help Beethoven instances find each other.
  """

  use GenServer
  require Logger
  alias __MODULE__.Lib
  alias Beethoven.Utils
  alias Beethoven.RootSupervisor

  #
  #
  #
  @doc """
  Starts server as a child of the root supervisor.
  Operation runs from a task to avoid hanging the caller waiting for init.
  """
  @spec async_start() :: :ok
  def async_start() do
    {:ok, _pid} =
      Task.start(fn ->
        Supervisor.start_child(RootSupervisor, __MODULE__)
      end)

    :ok
  end

  #
  #
  #
  @doc """
  Starts server as a child of the root supervisor.
  Operation runs from a task to avoid hanging the caller waiting for init.
  (random number between 2.5-5.75 seconds)
  """
  @spec async_timed_start() :: :ok
  def async_timed_start() do
    {:ok, _pid} =
      Task.start(fn ->
        # backoff in milliseconds (random number between 2.5-5.75 seconds)
        :ok = Utils.backoff_n(Listener.AsyncStart, 10, 9, 250)
        Supervisor.start_child(RootSupervisor, __MODULE__)
      end)

    :ok
  end

  #
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
  #
  # Callback for genserver start calls.
  @impl true
  def init(_args) do
    # Start Task manager for requests
    {:ok, _taskSup_pid} = Task.Supervisor.start_link(name: Beethoven.Core.Listener.TaskSupervisor)
    #
    # pull port from env file. Default to 33000 otherwise
    listener_port = Utils.get_app_env(:listener_port, 33000)
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
          :ok = GenServer.cast(__MODULE__, :accept)
          socket

        #
        # Failed -> IP already in use
        {:error, :eaddrinuse} ->
          Logger.warning(
            "Failed to bind listener socket to port [#{port_string}] as the port is already in-use. This is not an issue in ':clustered' mode."
          )

          exit(
            "Failed to bind listener socket to port [#{port_string}] as the port is already in-use."
          )

        #
        # Failed -> Unmapped
        {:error, _error} ->
          Logger.error(
            "Unexpected error occurred while binding listener socket to port [#{port_string}]."
          )

          exit(
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
    Logger.debug("Listener now accepting requests.")
    #
    # Start accept/serve loop
    :ok = accept(socket)
    #
    # call back to self to loop
    :ok = GenServer.cast(self(), :accept)
    #
    # End cast
    {:noreply, socket}
  end

  #
  #
  #
  @doc """
  TCP accept loop. When server gets a request
  """
  @spec accept(any()) :: :ok
  def accept(socket) do
    # FIFO accept the request from the socket buffer.
    # This Fun is blocking until a request is received.
    {:ok, client_socket} = :gen_tcp.accept(socket)
    # Spawn working thread to serve the response
    {:ok, pid} =
      Task.Supervisor.start_child(
        Beethoven.Core.Listener.TaskSupervisor,
        # redirect request into a task PID
        fn -> Lib.serve(client_socket) end
      )

    # transfer ownership of the socket request to the worker PID
    :gen_tcp.controlling_process(client_socket, pid)
  end
end
