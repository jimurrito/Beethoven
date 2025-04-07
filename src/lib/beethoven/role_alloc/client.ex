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
end
