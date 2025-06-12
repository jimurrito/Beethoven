defmodule Beethoven.Worm do
  @moduledoc """
  GenServer to allow for remote code execution between management and worker Highbid nodes.
  Mgmt nodes will remotely spawn and manage these PIDs from afar.
  """

  require Logger
  use GenServer

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # GenServer callback functions
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
  def init(_init_args) do
    Logger.info(status: :startup)
    {:ok, :ok}
  end

  #
  #
  @impl true
  def handle_call({:join_mnesia, node}, _from, state) do
    Logger.warning(mgmt_joined_mnesia: node)
    _ = :mnesia.change_config(:extra_db_nodes, [node])
    {:reply, :ok, state}
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Internal API
  #

  #
  #
  # Fn to streamline execution of functions on other nodes in the cluster.
  @spec remote_call((-> any()), node(), integer()) :: any() | {:error, :timeout}
  defp remote_call(fun, host, timeout \\ 1_000) do
    # generate seed for tracking
    seed = :crypto.strong_rand_bytes(16)
    # ownPID
    ownPid = self()
    #
    # Fun that will be ran in the remote host
    remote_fun = fn ->
      # run input fn
      result = fun.()
      # Send back to original caller
      _ = send(ownPid, {:remote_call, seed, result})
    end

    # Spawn PID on remote node
    _ = Node.spawn(host, remote_fun)

    # Await response
    receive do
      {:remote_call, ^seed, response} ->
        response
    after
      # Timeout awaiting response
      timeout ->
        {:error, :timeout}
    end
  end

  #
  #
  # Calls the Worm server on a given node.
  @spec call(node(), any()) :: {:ok, any()} | :timeout
  defp call(node, request) do
    mod = __MODULE__

    fn ->
      Process.whereis(mod)
      |> case do
        nil -> :not_running
        _pid -> {:ok, GenServer.call(mod, request)}
      end
    end
    |> remote_call(node)
  end

  #
  #
  # Casts the Worm server on a given node.
  @spec cast(node(), any()) :: :ok | :timeout
  def cast(node, request) do
    mod = __MODULE__

    fn ->
      Process.whereis(mod)
      |> case do
        nil -> :not_running
        _pid -> GenServer.cast(mod, request)
      end
    end
    |> remote_call(node)
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Public API
  #

  #
  #
  @doc """
  Adds calling MGMT node to mnesia cluster.
  """
  @spec join_mnesia(node()) :: :ok
  def join_mnesia(node) do
    {:ok, :ok} = call(node, {:join_mnesia, node()})
    :ok
  end

  #
  #
end
