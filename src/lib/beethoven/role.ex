defmodule Beethoven.Role do
  @moduledoc """
  Handles role re/assignment between clusters.
  """

  use GenServer
  require Logger

  alias Beethoven.Core, as: BeeServer
  alias Beethoven.Tracker
  alias Beethoven.Utils
  #
  #
  #
  #
  # Entry point for Supervisors
  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # Entry point for Supervisors
  def start(_args) do
    GenServer.start(__MODULE__, [], name: __MODULE__)
  end

  #
  #
  #
  #
  #
  @impl true
  def init(_args) do
    #
    # Subscribe to Mnesia - Monitor for new node
    #{:ok, _node} = Tracker.subscribe()
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
    ref = Process.monitor(pid)
    # Initiate check function
    GenServer.cast(__MODULE__, :check)
    #
    {:ok, %{roles: roles, super_pid: {pid, ref}, role_pids: %{}}}
  end

  #
  #
  #
  #
  #
  #
  # Check role cast, but when we have no roles
  @impl true
  def handle_cast(:check, %{roles: roles, super_pid: super_pid, role_pids: %{}})
      when roles == %{} do
    Logger.notice(
      "Role check was initiated for Beethoven.RoleServer, but there are no roles to track. Nothing to do."
    )

    {:noreply, %{roles: roles, super_pid: super_pid, role_pids: %{}}}
  end

  #
  #
  #
  #
  #
  # Check roles
  @impl true
  def handle_cast(:check, %{roles: roles, super_pid: super_pid, role_pids: role_pids}) do
    #
    # IO.inspect({:roles_before, %{roles: roles, super_pid: super_pid, role_pids: role_pids}})
    # Determine if we are in standalone or clustered mode
    # In standalone, assume all roles. In Cluster, poll Mnesia
    mode = GenServer.call(BeeServer, :get_mode)
    Logger.debug("RoleServer operating in (:#{mode}) mode.")

    mode
    |> case do
      # Standalone mode => assume all roles
      :standalone ->
        # Spawn children in RoleSupervisor
        new_role_pids =
          roles
          |> Enum.map(fn {name, module, args, _count} ->
            Logger.info("Starting role (:#{name}) on node (#{node()}).")

            Logger.debug(
              "Adding role (:#{name}) to DynamicSupervisor (Beethoven.Role.RoleSupervisor)"
            )

            # Spawn role in Dynamic supervisor
            {:ok, role_pid} =
              DynamicSupervisor.start_child(Beethoven.Role.RoleSupervisor, {module, args})

            Logger.debug("Monitoring Role (:#{name}) on node (#{node()}).")
            role_ref = Process.monitor(role_pid)
            #
            %{} |> Map.put(name, {role_pid, role_ref})
            #
          end)

        # Merge maps
        role_pids = role_pids |> Utils.bulk_put(new_role_pids)
        node_roles = role_pids |> Map.keys()

        # Update Mnesia
        Logger.debug("Writing the roles for node (#{node()}) to BeethovenTracker.")

        {:atomic, :ok} =
          :mnesia.transaction(fn ->
            :mnesia.write(
              {BeethovenTracker, node(), node_roles, :online, DateTime.now!("Etc/UTC")}
            )
          end)

        {:noreply, %{roles: roles, super_pid: super_pid, role_pids: role_pids}}

      #
      #
      #
      # Clustered mode => poll for role assignment.
      :clustered ->
        # Backoff | 100 - 149 milliseconds
        Utils.backoff(100, 49)

        # Performs operations in transaction
        # See to see what roles are being hosted
        Logger.debug("Getting hosted roles from BeethovenTracker.")

        {:atomic, node_roles} =
          :mnesia.transaction(fn ->
            # Checks to see what roles are currently being served
            # Get nodes in cluster
            :mnesia.all_keys(BeethovenTracker)
            |> Enum.map(fn node ->
              # get roles for the node
              :mnesia.read({BeethovenTracker, node})
              |> case do
                # Node is a member (no role) => []
                [{BeethovenTracker, ^node, :member, _health, _last_change}] -> []
                # Node has roles of some kind => [atom()]
                [{BeethovenTracker, ^node, node_roles, _health, _last_change}] -> node_roles
              end
            end)
          end)

        # Flatten list of node roles
        node_roles = node_roles |> List.flatten()
        # Filter the roles that are being hosted from the ones defined in the config.
        # returned roles need to be deployed on the node.
        roles
        |> Enum.filter(fn {role, _mod, _args, inst} ->
          # count the instances of a given role hosted within the cluster
          role_count =
            Enum.count(node_roles, fn
              ^role -> true
              _ -> false
            end)

          # validate count
          cond do
            # already has the correct amount of role instances
            role_count == inst -> false
            # has less then the desired instances of the role
            role_count < inst -> true
            # has more then the desired amount (Not good!)
            role_count > inst -> false
          end
        end)
        |> case do
          # no roles needed
          [] ->
            Logger.info("No roles missing from config. Roles state is compliant.")
            {:noreply, %{roles: roles, super_pid: super_pid, role_pids: role_pids}}

          # Some roles
          roles_to_deploy ->
            Logger.info(
              "(#{length(roles_to_deploy) |> Integer.to_string()}) roles required to be deployed."
            )

            Logger.debug("Picking role to deploy at random.")

            # Randomly pick (1) role and deploy it. Check will run again after the deployment, and this process will repeat.
            # the reason for this repetition is to ensure other nodes in the custer have a chance to take on one of the other roles.
            role_to_deploy = Enum.random(roles_to_deploy)
            Logger.info("Deploying role (:#{role_to_deploy |> elem(0)}) to node (#{node()}).")
            :ok = GenServer.cast(__MODULE__, {:add_role, role_to_deploy})
            #
            {:noreply, %{roles: roles, super_pid: super_pid, role_pids: role_pids}}
        end
    end
  end

  #
  #
  #
  #
  #
  #
  # Adds a single role to the server.
  @impl true
  def handle_cast({:add_role, {name, module, args, _inst}}, %{
        roles: roles,
        super_pid: super_pid,
        role_pids: role_pids
      }) do
    # Spawn children in RoleSupervisor
    Logger.info("Starting Role (:#{name}) on node (#{node()}).")
    # Spawn role in Dynamic supervisor
    {:ok, role_pid} =
      DynamicSupervisor.start_child(Beethoven.Role.RoleSupervisor, {module, args})

    Logger.debug("Monitoring Role (:#{name}) on node (#{node()}).")
    role_ref = Process.monitor(role_pid)
    # Add new role pid+ref to state obj
    role_pids = role_pids |> Map.put(name, {role_pid, role_ref})
    #
    # List of roles this node is running now
    node_roles = role_pids |> Map.keys()
    #
    # Write role change to BeethovenTracker
    Logger.debug(
      "Writing the (#{length(node_roles) |> Integer.to_string()}) roles for node (#{node()}) to BeethovenTracker."
    )

    {:atomic, :ok} =
      :mnesia.transaction(fn ->
        :mnesia.write({BeethovenTracker, node(), node_roles, :online, DateTime.now!("Etc/UTC")})
      end)

    # Initiate a new check -> This ensures no other roles are needed.
    Logger.debug("Casting ':check' action again to ensure there are no other roles needed.")
    :ok = GenServer.cast(__MODULE__, :check)
    #
    {:noreply, %{roles: roles, super_pid: super_pid, role_pids: role_pids}}
  end

  #
  #
  #
  #
  # Kill a role provided
  @impl true
  def handle_cast({:kill_role, name}, %{
        roles: roles,
        super_pid: super_pid,
        role_pids: role_pids
      }) do
    # get ref and pid from role_pids map
    Map.get(role_pids, name)
    |> case do
      # Got role info
      {pid, ref} ->
        # stop monitoring
        Logger.debug("Stopped monitoring role (#{name}) on node (#{node()}).")
        true = Process.demonitor(ref)
        # Kill role
        Logger.warning("Role (#{name}) was killed by the RoleServer.")
        Process.exit(pid, "Role (#{name}) was killed by the RoleServer.")
        {:noreply, %{roles: roles, super_pid: super_pid, role_pids: role_pids}}

      # role not hosted on the node
      nil ->
        Logger.warning(
          "Role (#{name}) was requested to be killed, but it does not run on this node (#{node()})."
        )

        {:noreply, %{roles: roles, super_pid: super_pid, role_pids: role_pids}}
    end
  end

  #
  #
  #
  #
  #
  # Ignore Mnesia updates from the same node.
  @impl true
  def handle_info(
        {:mnesia_table_event, {:write, BeethovenTracker, {_, node, _, _, _}, _, {:tid, _, pid}}},
        state
      )
      when node == node() and pid == self() do
    {:noreply, state}
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
