defmodule Beethoven.RoleAlloc do
  @moduledoc """
  Role Allocation Server. Works as a queue to assign roles needed by the configuration.
  """

  use GenServer
  require Logger

  alias __MODULE__.State

  #
  #
  def start_link do
    GenServer.start_link(__MODULE__, [], [])
  end

  #
  #
  @impl true
  def init(_arg) do
    # register self in global

    #
    # get roles from config.exs
    roles =
      Application.fetch_env(:beethoven, :roles)
      |> case do
        {:ok, value} ->
          value

        :error ->
          Logger.notice(":roles is not set in config/*.exs. Assuming no roles.")
          []
      end

    # Initiates a role assignment check against the mnesia database
    GenServer.call(__MODULE__, :check)

    {:ok, %State{ready?: false, roles: roles, queue: :queue.new()}}
  end

  #
  # Checks what roles are needed.
  @impl true
  def handle_cast(:check, state) do
    {:noreply, state}
  end

  #
  # Logic for when a node goes down.
  @impl true
  def handle_cast({:node_down, node}, state) do
    {:noreply, state}
  end

  #
  # Call to see if role allocator is ready
  @impl true
  def handle_call(:ready?, _from, %State{ready?: state, roles: roles, queue: queue}) do
    {:reply, state, %State{ready?: state, roles: roles, queue: queue}}
  end




end
