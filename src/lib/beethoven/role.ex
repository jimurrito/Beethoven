defmodule Beethoven.Role do
  @moduledoc """
  Handles role re/assignment between clusters.
  """

  use GenServer
  require Logger

  alias Beethoven.Core, as: BeeServer
  alias Beethoven.Tracker

  #
  #
  #
  #
  # Entry point for Supervisors
  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  #
  #
  #
  #
  #
  @impl true
  def init(_args) do
    # Track all nodes
    Node.list()
    |> Enum.each(fn nodeName ->
      # Start monitoring the calling node
      Logger.info("Started monitoring Node (#{nodeName}).")
      true = Node.monitor(nodeName, true)
    end)

    # Subscribe to Mnesia - Monitor for new node
    {:ok, _node} = Tracker.subscribe()
    # Get application config for roles
    roles =
      Application.fetch_env(:beethoven, :roles)
      |> case do
        {:ok, value} ->
          value

        :error ->
          Logger.notice(":roles is not set in config/*.exs. Assuming no roles.")
          []
      end

    # Start Dynamic Supervisor for roles
    {:ok, pid} =
      DynamicSupervisor.start_link(strategy: :one_for_one, name: Beethoven.Role.RoleSupervisor)

    # Monitor supervisor
    _ref = Process.monitor(pid)
    #
    GenServer.cast(__MODULE__, :check)
    #
    {:ok, roles}
  end

  #
  #
  #
  # Check role cast, but when we have no roles
  @impl true
  def handle_cast(:check, roles) when roles == [] do
    Logger.notice(
      "Role check was initiated for Beethoven.RoleServer, but there are no roles to track. Nothing to do."
    )

    {:noreply, roles}
  end

  #
  # Check roles
  @impl true
  def handle_cast(:check, roles) do
    IO.inspect({:roles, roles})
    # Determine if we are in standalone or clustered mode
    # In standalone, assume all roles. In Cluster, poll Mnesia
    mode = GenServer.call(BeeServer, :get_mode)
    Logger.info("RoleServer operating in (:#{mode}) mode.")

    mode
    |> case do
      # Standalone mode => assume all roles
      :standalone ->
        # Spawn children in RoleSupervisor
        roles
        |> Enum.map(fn {name, module, args, _count} ->
          Logger.info("Starting Role (:#{name}) on node (#{node()}).")
          {:ok, role_pid} = DynamicSupervisor.start_child(Beethoven.Role.RoleSupervisor, {module, args})
          #
          Logger.debug("Monitoring Role (:#{name}) on node (#{node()}).")
          ref = Process.monitor(role_pid)
        end)

        {:noreply, roles}

      # Clustered mode => poll for role assignment.
      :clustered ->
        # Checks to see what roles are currently being served
        # Get nodes in cluster
        _nodes = :mnesia.dirty_all_keys(BeethovenTracker)

        {:noreply, roles}
    end
  end

  #
  #
  #
  #
  #
  # Catch All handle_info
  # MUST BE AT BOTTOM OF MODULE FILE **WITHOUT THIS, COORDINATOR GENSERVER WILL CRASH ON UNMAPPED MSG!!**
  @impl true
  def handle_info(msg, state) do
    Logger.warning("[unexpected] Beethoven.RoleServer received an un-mapped message.")
    IO.inspect({:unmapped_msg, msg})
    {:noreply, state}
  end
end
