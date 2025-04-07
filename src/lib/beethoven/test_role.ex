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
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  #
  #
  @impl true
  def init(args) do
    Logger.info("Test GenServer Started!")
    IO.inspect({:test_role_running, {TestRole, :params, args}})
    {:ok, args}
  end

  #
  #
  @impl true
  def handle_call({:echo, payload}, _from, state) do
    Logger.notice("Echo call - local!")
    IO.inspect({:test_role_called, %{data: payload}})
    {:reply, payload, state}
  end

  #
  #
end
