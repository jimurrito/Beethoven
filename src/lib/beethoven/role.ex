defmodule Beethoven.Role do
  @moduledoc """
  Handles role re/assignment between clusters.
  """

  use GenServer
  require Logger
  alias Beethoven.Role.RoleSupervisor
  alias Beethoven.Tracker
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
  Entry point for Supervisors. Links calling PID this this child pid.
  """
  @spec start_link(any()) :: {:ok, pid()}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  #
  #
  # Callback used on start/3 and start_link/3
  @impl true
  def init(_args) do
    #
    Logger.info("Starting Beethoven RoleServer")
    # Get application config for roles
    roles = Utils.get_role_config()

    # Start Dynamic Supervisor for roles
    # this ensures roles are able to fail without causing a cascading failure.
    {:ok, _pid} =
      DynamicSupervisor.start_link(
        strategy: :one_for_one,
        name: RoleSupervisor,
        max_restarts: 15
      )

    # return initial state
    {:ok, %{roles: roles, role_pids: %{}}}
  end

  #
  #
  #
  # Adds a single role to the server.
  # This is usually triggered by the RoleAlloc Server.
  # {seed, callerPid} is used to call back to the RoleAlloc Server globally.
  @impl true
  def handle_cast({:add_role, {seed, callerPid}, role}, %{
        roles: roles,
        role_pids: role_pids
      }) do
    # Spawn children in RoleSupervisor
    Logger.info("Role (:#{role}) was assigned to this node.")
    # get target role from state
    {module, args, _inst} = roles |> Map.get(role)
    #
    # Spawn role in Dynamic supervisor
    DynamicSupervisor.start_child(RoleSupervisor, {module, args})
    |> case do
      #
      # Pid was created
      {:ok, role_pid} ->
        Logger.info("Role (:#{role}) was successfully spawned on node (#{node()}).")
        Logger.debug("Monitoring role (:#{role}) on node (#{node()}).")
        role_ref = Process.monitor(role_pid)
        # Add new role pid+ref to state obj
        role_pids = role_pids |> Map.put(role, {role_pid, role_ref})
        #
        # List of roles this node is running now
        node_role_list = role_pids |> Map.keys()
        #
        Logger.debug(
          "Writing the (#{length(node_role_list) |> Integer.to_string()}) roles for node (#{node()}) to Beethoven.Tracker."
        )

        # Write role change to Beethoven.Tracker
        :ok = Tracker.add_role(node(), role)
        # Tell caller we succeeded.
        _ = send(callerPid, {:assigned, seed})
        #
        {:noreply, %{roles: roles, role_pids: role_pids}}

      #
      # PID failed to be created.
      msg ->
        Logger.critical(%{role_start_error: msg})
        # Tell caller we failed.
        send(callerPid, {:error, seed, msg})
        #
        {:noreply, %{roles: roles, role_pids: role_pids}}
    end
  end

  #
  #
  #
  #
  # Kill a role that is assigned to his node.
  # This is usually triggered by the RoleAlloc Server.
  # {seed, callerPid} is used to call back to the RoleAlloc Server globally.
  # Expected responses: [:removed, :role_not_hosted]
  @impl true
  def handle_cast({:kill_role, {seed, callerPid}, role}, %{
        roles: roles,
        role_pids: role_pids
      }) do
    # Pop item out of map
    {role_item, new_role_pids} = Map.pop(role_pids, role)
    # get ref and pid from role_pids map
    role_item
    |> case do
      # Got role info
      {role_pid, ref} ->
        # stop monitoring
        Logger.debug("Stopped monitoring role (#{role}) on node (#{node()}).")
        true = Process.demonitor(ref)
        # Kill role
        Logger.notice("Role (#{role}) was killed by RoleAlloc Server.")
        :ok = DynamicSupervisor.terminate_child(RoleSupervisor, role_pid)
        # let caller know the result
        _ = send(callerPid, {:removed, seed})

        #
        {:noreply, %{roles: roles, role_pids: new_role_pids}}

      # role not hosted on the node
      nil ->
        Logger.warning(
          "Role (#{role}) was requested to be killed, but it does not run on this node (#{node()})."
        )

        # Tell caller we failed
        _ = send(callerPid, {:error, seed, :role_not_hosted})

        {:noreply, %{roles: roles, role_pids: role_pids}}
    end
  end
end
