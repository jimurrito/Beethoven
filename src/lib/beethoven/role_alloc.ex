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
      when retries <= 10 do
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
            # 1 second
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
        retries: _retries
      }) do
    Logger.info("Beethoven Role Allocator clean-up job triggered.")
    # clean up offline nodes -> returns roles removed from the nodes.
    # Converts roles to queue and merge the two.
    new_role_queue =
      Tracker.clear_offline_roles()
      # Remove any built-in roles
      |> Tracker.remove_builtins()
      # Convert to queue
      |> :queue.from_list()
      # append to role queue
      |> :queue.join(role_queue)

    # Make new host_queue
    new_host_queue = make_host_queue()

    # Count diffs
    host_diff = :queue.len(new_host_queue) - :queue.len(host_queue)
    role_diff = :queue.len(new_role_queue) - :queue.len(role_queue)

    Logger.info(
      "Clean up job completed. Changes: [(#{to_string(host_diff)}) Node(s)] | [(#{to_string(role_diff)}) Role(s)]"
    )

    # triggers assignment loop
    :ok = GenServer.cast(__MODULE__, :assign)

    {:noreply, %{role: roles, role_queue: new_role_queue, host_queue: new_host_queue, retries: 0}}
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
  #
  #
  # Generates a new host queue based on how many roles the nodes have.
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
