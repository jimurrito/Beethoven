defmodule Beethoven.TestRole do
  @moduledoc """
  Test role to test RoleServer operations.

  A role is just another PID of some kind. Module must have `start_link/1` that returns {:ok, pid()} or the role will fail to load.

  """

  use GenServer
  require Logger

  @doc """
  Entry point for RolServer/Supervisor
  """
  def start_link(_args) do
    GenServer.start(__MODULE__, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    {:ok, []}
  end
end
