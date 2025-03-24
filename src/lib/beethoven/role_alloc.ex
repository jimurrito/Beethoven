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
  @impl true
  def init(_arg) do
    # Register PID globally
    # :global.register_name(__MODULE__, self())
    # Set role for node
    :ok = Tracker.add_role(node(), :been_alloc)
    # Clean up any other
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

    host_queue =
      Tracker.get_active_roles_by_host()
      # sort by amount of jobs held
      |> Enum.sort_by(fn [_node, role_count] -> role_count end)
      # Return list of only hosts
      |> Enum.map(fn [node, _role_count] -> node end)
      |> :queue.from_list()

    Logger.info(
      "Found (#{:queue.len(host_queue)}) nodes in cluster and (#{:queue.len(role_queue)}) roles to be assigned"
    )

    # start assignment if the queue has length

    if :queue.len(role_queue) > 0 do
      :ok = GenServer.cast(__MODULE__, :assign)
    end

    #
    {:ok, %{role: roles, role_queue: role_queue, host_queue: host_queue}}
  end

  #
  #
  # Cast to trigger role assignment
  @impl true
  def handle_cast(:assign, %{role: roles, role_queue: role_queue, host_queue: host_queue}) do
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
        {:noreply, %{role: roles, role_queue: role_queue, host_queue: host_queue}}

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
          {:noreply, %{role: roles, role_queue: role_queue, host_queue: new_host_queue}}
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
              {:noreply, %{role: roles, role_queue: new_role_queue, host_queue: new_host_queue}}

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
              {:noreply, %{role: roles, role_queue: role_queue, host_queue: new_host_queue}}
          after
            # 1 second
            1_000 ->
              Logger.alert("Role assignment for role (#{q_role}) on node (#{q_host}) timed out.")
              # Add host to back of the queue
              new_host_queue = :queue.in(q_host, new_host_queue)
              # Recurse - try on another host
              GenServer.cast(__MODULE__, :assign)
              #
              {:noreply, %{role: roles, role_queue: role_queue, host_queue: new_host_queue}}
          end
        end
    end

    #
  end
end
