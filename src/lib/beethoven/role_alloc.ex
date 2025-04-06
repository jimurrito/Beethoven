defmodule Beethoven.RoleAlloc do
  @moduledoc """
  Role Allocation Server. Works as a queue to assign roles needed by the configuration.

  # TODO
  - Fix bug where a node goes down, but comes back up before it is updated in tracker
    ex: Node (nodeY@127.0.0.1) is back online
    Potential solutions
    - a task that waits and calls the role alloc server back to let it know if it needs to remove the node or not?

  """

  use GenServer
  require Logger
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
  def start_link([]) do
    # Check if already hosted
    Tracker.is_role_hosted?(:been_alloc)
    |> if do
      # Hosted
      # Service is registered

      Logger.warning(
        "Beethoven Role Allocator is already running in the cluster. This is not an error."
      )

      {:error, :already_hosted}
    else
      Logger.info("Beethoven Role Allocator is not running in the cluster. Starting now.")

      # not hosted
      GenServer.start_link(__MODULE__, [], name: __MODULE__)
    end
  end

  #
  #
  #
  #
  @impl true
  def init(_arg) do
    # Sets name globally
    :global.register_name(__MODULE__, self())
    # Set role for node
    :ok = Tracker.add_role(node(), :been_alloc)
    # monitor all active nodes
    :ok = Utils.monitor_all_nodes(true)
    # Subscribe to tracker changes
    {:ok, _node} = Tracker.subscribe()
    #
    Logger.info("Starting Beethoven Role Allocator.")
    roles = Utils.get_role_config()
    Logger.debug(role_alloc_roles: roles)
    #
    Logger.debug("Creating list of roles needed for the cluster.")

    # role_list represents lists that are needed according to the runtime config provided in config.exs.
    # get roles by key - will de duplicate if multiple instances are needed
    # converts the list of maps from config to a list of atoms
    role_list =
      roles
      |> Enum.map(fn {name, {_mod, _args, inst}} ->
        # range to create multiple instances
        1..inst
        |> Enum.map(fn _ -> name end)
      end)
      # Flatten list
      |> List.flatten()

    # Filter what roles are needed based on what is in mnesia.
    # Essentially removes roles hosted on Mnesia from the ones needed in the config.
    Logger.debug("Filtering roles needed to roles hosted in Tracker.")
    roles_needed = Tracker.find_work(role_list)
    # convert list to queue
    role_queue = :queue.from_list(roles_needed)
    #
    # Get hosts - sort by hosts held.
    Logger.debug("Creating queue based on node Role load.")

    host_queue = make_host_queue()

    Logger.info(
      "Found (#{:queue.len(host_queue)}) nodes in cluster and (#{:queue.len(role_queue)}) roles to be assigned"
    )

    Logger.debug(hosts: host_queue, roles: role_queue)

    # triggers cleanup job -. Ensures there are no stragglers after a failover
    # Cleanup will trigger an assignment loop
    :ok = GenServer.cast(__MODULE__, :clean_up)

    # return
    {:ok, %{role: roles, role_queue: role_queue, host_queue: host_queue, retries: 0}}
  end

  #
  #
  #
  # Cast to trigger role assignment
  @impl true
  def handle_cast(:assign, %{
        role: roles,
        role_queue: role_queue,
        host_queue: host_queue,
        retries: retries
      })
      when retries < 11 do
    Logger.debug("Starting assignment.")
    # get host from queue
    {{:value, q_host}, new_host_queue} = :queue.out(host_queue)
    #
    # get items from role queue
    :queue.out(role_queue)
    |> case do
      #
      # no more roles in queue - end cast
      {:empty, role_queue} ->
        Logger.info("No more roles to assign. Awaiting changes to state.")
        {:noreply, %{role: roles, role_queue: role_queue, host_queue: host_queue, retries: 0}}

      #
      # value from queue -> continue on
      {{:value, q_role}, new_role_queue} ->
        Logger.debug("Attempting assignment of role (#{q_role}) to node (#{q_host}).")
        #
        # Check if host is running the desired role
        if Tracker.is_host_running_role?(q_host, q_role) do
          # running role
          Logger.debug("Node (#{q_host}) is already running an instance of role (#{q_role}).")
          #
          # Try again, but with the next host
          new_host_queue = :queue.in(q_host, new_host_queue)
          # Recurse
          GenServer.cast(__MODULE__, :assign)
          #
          {:noreply,
           %{
             role: roles,
             role_queue: role_queue,
             host_queue: new_host_queue,
             retries: retries + 1
           }}
        else
          # not running role
          Logger.info("Assigning role (#{q_role}) to node (#{q_host}).")
          #
          # generate seed for tracking (10_000-99_9999)
          seed = :rand.uniform(90_000) + 9_999
          #
          # ownPID
          ownPid = self()

          #
          # Run locally if target server is local
          if q_host == node() do
            # Run locally
            GenServer.cast(Beethoven.Role, {:add_role, {seed, ownPid}, q_role})
          else
            # Call roleServer in target node to assign the role
            fun = fn ->
              GenServer.cast(Beethoven.Role, {:add_role, {seed, ownPid}, q_role})
            end

            _ = Node.spawn(q_host, fun)
          end

          #
          # Await message back from server
          # Filter response based on seed and response type
          receive do
            #
            # Role Server assigned role successfully
            {:assigned, ^seed} ->
              Logger.info("Successfully assigned role (#{q_role}) to node (#{q_host}).")
              #
              # Add host to back of the queue
              new_host_queue = :queue.in(q_host, new_host_queue)
              # Recurse
              GenServer.cast(__MODULE__, :assign)
              #
              {:noreply,
               %{role: roles, role_queue: new_role_queue, host_queue: new_host_queue, retries: 0}}

            #
            # RoleServer failed to add role
            {:error, ^seed, msg} when is_binary(msg) ->
              Logger.error(
                "RoleServer on node (#{q_host}) failed to create instance of role (#{q_role}). [#{msg}]"
              )

              # Add host to back of the queue
              new_host_queue = :queue.in(q_host, new_host_queue)
              # Recurse - try on another host
              GenServer.cast(__MODULE__, :assign)
              #
              {:noreply,
               %{
                 role: roles,
                 role_queue: role_queue,
                 host_queue: new_host_queue,
                 retries: retries + 1
               }}
          after
            # 1 second timeout threshold for role provisioning on target
            1_000 ->
              Logger.alert("Role assignment for role (#{q_role}) on node (#{q_host}) timed out.")
              # Add host to back of the queue
              new_host_queue = :queue.in(q_host, new_host_queue)
              # Recurse - try on another host
              GenServer.cast(__MODULE__, :assign)
              #
              {:noreply,
               %{
                 role: roles,
                 role_queue: role_queue,
                 host_queue: new_host_queue,
                 retries: retries + 1
               }}
          end
        end
    end
  end

  #
  #
  #
  # Assign when we have hit 11+ failed requests
  # Kills assign loop.
  @impl true
  def handle_cast(:assign, %{
        role: roles,
        role_queue: role_queue,
        host_queue: host_queue,
        retries: retries
      })
      when retries > 10 do
    Logger.warning(
      "Beethoven RoleAllocator Server has failed to assign roles (#{to_string(retries)}) times. Will await next state change."
    )

    {:noreply, %{role: roles, role_queue: role_queue, host_queue: host_queue, retries: 0}}
  end

  #
  #
  # gets roles hosted by offline nodes and add add them to the job queue.
  # Also removes any offline nodes in the host_queue variable.
  # Should be triggered occasionally and when a node goes down.
  @impl true
  def handle_cast(:clean_up, %{
        role: roles,
        role_queue: role_queue,
        host_queue: host_queue,
        retries: retries
      }) do
    Logger.info("Beethoven Role Allocator clean-up job triggered.")
    # clean up offline nodes -> returns roles removed from the nodes.
    removed_roles = Tracker.clear_offline_roles()

    Logger.info(
      "(#{length(removed_roles)}) Roles have been cleared from the Tracker for reassignment."
    )

    Logger.debug("Creating list of roles needed for the cluster.")

    #
    # role_list represents lists that are needed according to the runtime config provided in config.exs.
    # get roles by key - will de duplicate if multiple instances are needed
    # converts the list of maps from config to a list of atoms
    role_list =
      roles
      |> Enum.map(fn {name, {_mod, _args, inst}} ->
        # range to create multiple instances
        1..inst
        |> Enum.map(fn _ -> name end)
      end)
      # Flatten list
      |> List.flatten()

    # Filter what roles are needed based on what is in mnesia.
    # Essentially removes roles hosted on Mnesia from the ones needed in the config.
    Logger.debug("Filtering roles needed to roles hosted in Tracker.")
    roles_needed = Tracker.find_work(role_list)

    # convert list to queue
    new_role_queue = :queue.from_list(roles_needed)

    # Make new host_queue
    new_host_queue = make_host_queue()

    # Count diffs
    host_diff = :queue.len(new_host_queue) - :queue.len(host_queue)
    role_diff = :queue.len(new_role_queue) - :queue.len(role_queue)

    Logger.info(
      "Clean up job completed. Changes: [(#{to_string(host_diff)}) Node(s)] | [(#{to_string(role_diff)}) Role(s)]"
    )

    Logger.debug(new: {new_host_queue, new_role_queue}, old: {host_queue, role_queue})

    # triggers assignment loop
    :ok = GenServer.cast(__MODULE__, :assign)

    {:noreply,
     %{role: roles, role_queue: new_role_queue, host_queue: new_host_queue, retries: retries}}
  end

  #
  #
  #
  # Handles :nodedown monitoring messages.
  @impl true
  def handle_info({:nodedown, nodeName}, state) when is_atom(nodeName) do
    # triggers cleanup job
    :ok = GenServer.cast(__MODULE__, :clean_up)
    {:noreply, state}
  end

  #
  #
  # Handles :clean_up requests from other nodes.
  @impl true
  def handle_info(:clean_up, state) do
    # triggers cleanup job
    :ok = GenServer.cast(__MODULE__, :clean_up)
    {:noreply, state}
  end

  #
  #
  # handles :assign requests from other nodes
  def handle_info(:assign, state) do
    # triggers cleanup job
    :ok = GenServer.cast(__MODULE__, :assign)
    {:noreply, state}
  end

  #
  #
  #
  @impl true
  def handle_info({:mnesia_table_event, msg}, %{
        role: roles,
        role_queue: role_queue,
        host_queue: host_queue,
        retries: retries
      }) do
    # Logger.warning("MNESIA EVENT")
    # IO.inspect({:event, msg})
    {:ok, new_host_queue} =
      msg
      |> case do
        #
        # New node was added to the 'Beethoven.Tracker' table
        {:write, Beethoven.Tracker, {Beethoven.Tracker, nodeName, _, :online, _}, [], _pid_struct} ->
          #
          Logger.info("A new node (#{nodeName}) has joined the cluster. Starting Assign job.")
          GenServer.cast(__MODULE__, :assign)
          # monitor node
          Utils.monitor_node(nodeName, true)
          # Add to queue
          host_queue = nodeName |> :queue.in(host_queue)
          {:ok, host_queue}

        # Node changed from online to offline in 'Beethoven.Tracker' table
        {:write, Beethoven.Tracker, {Beethoven.Tracker, nodeName, _, :offline, _},
         [{Beethoven.Tracker, nodeName, _, :online, _}], _pid_struct} ->
          #
          Logger.info("A cluster node (#{nodeName}) has gone offline. Starting Clean-up job.")
          GenServer.cast(__MODULE__, :clean_up)
          #
          Utils.monitor_node(nodeName, false)
          # remove from queue
          host_queue = nodeName |> :queue.delete(host_queue)
          {:ok, host_queue}

        # Node changed from offline to online in 'Beethoven.Tracker' table
        {:write, Beethoven.Tracker, {Beethoven.Tracker, nodeName, _, :online, _},
         [{Beethoven.Tracker, nodeName, _, :offline, _}], _pid_struct} ->
          #
          Logger.info("A cluster node (#{nodeName}) has came back online. Starting Assign job.")
          GenServer.cast(__MODULE__, :assign)
          # Add to queue
          host_queue = nodeName |> :queue.in(host_queue)
          {:ok, host_queue}

        # Catch all
        _ ->
          # return queue as-is
          {:ok, host_queue}
          #
          #
      end

    {:noreply,
     %{
       role: roles,
       role_queue: role_queue,
       host_queue: new_host_queue,
       retries: retries
     }}
  end

  #
  #
  #
  #
  # Generates a new host queue based on how many roles the nodes have.
  # Less roles == higher priority in the queue.
  defp make_host_queue() do
    Tracker.get_active_roles_by_host()
    # sort by amount of jobs held
    |> Enum.sort_by(fn [_node, roles] -> length(roles) end)
    # Return list of only hosts
    |> Enum.map(fn [node, _roles] -> node end)
    |> :queue.from_list()
  end

  #
  #
  #
end
