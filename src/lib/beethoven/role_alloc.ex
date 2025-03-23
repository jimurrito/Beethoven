defmodule Beethoven.RoleAlloc do
  @moduledoc """
  Role Allocation Server. Works as a queue to assign roles needed by the configuration.
  """

  use GenServer
  require Logger

  alias Beethoven.Tracker
  alias Beethoven.Utils

  #
  #
  def start([]) do
    # Check if it exists globally prior
    :global.whereis_name(__MODULE__)
    |> case do
      # Not in global registry
      :undefined ->
        GenServer.start(__MODULE__, [], [])

      # Service is registered
      _ ->
        Logger.notice(
          "Beethoven Role Allocator is already globally registered. Service will not run."
        )

        {:error, :already_globally_defined}
    end
  end

  #
  #
  @impl true
  def init(_arg) do
    Logger.info("Starting Beethoven Role Allocator.")
    #
    :global.register_name(__MODULE__, self())
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

    # get roles by key - will de duplicate if multiple instances are needed
    # converts the list of maps from config to a list of atoms
    role_list =
      roles
      |> Enum.map(fn {name, _mod, _args, inst} ->
        # range to create multiple instances
        1..inst
        |> Enum.map(fn _ -> name end)
      end)
      # Flatten list
      |> List.flatten()

    # Filter what roles are needed based on what is in mnesia
    roles_needed = Tracker.find_work(role_list)
    # convert list to queue
    queue = :queue.from_list(roles_needed)
    #
    # Trigger assign
    :ok = GenServer.cast(__MODULE__, :assign)
    #
    {:ok, %{roles: roles, queue: queue}}
  end

  #
  #
  # Cast to trigger role assignment
  @impl true
  def handle_cast(:assign, %{roles: roles, queue: queue}) do
    # fun to be ran on each item used in queue
    fn role ->
      # 
      #
    end
  end

  #
  # Logic for when a node goes down.
  @impl true
  def handle_cast({:node_down, node}, state) do
    {:noreply, state}
  end
end
