defmodule Beethoven.RoleAlloc.Client do
  @moduledoc """
  Client Library for interacting with the RoleAlloc Server
  """

  alias Beethoven.RoleAlloc

  #
  #
  @doc """
  Starts Assignment loop on the RoleAlloc Server in the cluster.
  Assumes RoleServer is running locally.
  """
  @spec start_assign() :: :ok
  def start_assign() do
    GenServer.cast(RoleAlloc, :assign)
  end

  #
  #
  @doc """
  Starts clean up job on the RoleAlloc Server in the cluster.
  Assumes RoleServer is running locally.
  """
  @spec start_cleanup() :: :ok
  def start_cleanup() do
    GenServer.cast(RoleAlloc, :clean_up)
  end

  #
  #
  @doc """
  Same as `start_assign/0` but has a defined sleep before sending the cast.
  Job is done in a task to avoid hanging thread
  """
  @spec timed_assign(integer()) :: :ok
  def timed_assign(waitTime \\ 2_000) do
    {:ok, _pid} =
      fn ->
        :ok = Process.sleep(waitTime)
        :ok = start_assign()
      end
      |> Task.start()

    :ok
  end

  #
  #
  @doc """
  Same as `start_cleanup/0` but has a defined sleep before sending the cast.
  Job is done in a task to avoid hanging thread
  """
  @spec timed_cleanup(integer()) :: :ok
  def timed_cleanup(waitTime \\ 2_000) do
    {:ok, _pid} =
      fn ->
        :ok = Process.sleep(waitTime)
        :ok = start_cleanup()
      end
      |> Task.start()

    :ok
  end

  #
  #
  @doc """
  Instructs RoleAlloc Server to mark the provided node offline and start reassignment of its roles.
  Defaults to using the nodeName of the caller unless specified.
  """
  @spec prune(node(), integer()) :: :ok | {:error, :timeout}
  def prune(nodeName \\ node(), timeout \\ 1_000) do
    # generate seed for tracking (100_000-999_9999)
    seed = :rand.uniform(900_000) + 99_999

    # Spawn PID on remote node
    _pid = :global.send(RoleAlloc, {:prune, seed, self(), nodeName})

    # Await response
    receive do
      {:prune, ^seed, :ok} ->
        :ok
    after
      # Timeout awaiting response
      timeout ->
        {:error, :timeout}
    end
  end
end
