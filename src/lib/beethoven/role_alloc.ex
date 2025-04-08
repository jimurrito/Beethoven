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
  alias Beethoven.RoleAlloc.MnesiaNotify
  alias Beethoven.RoleAlloc.Lib
  alias Beethoven.Tracker
  alias Beethoven.Utils
  alias Beethoven.RootSupervisor
  alias Beethoven.Role.Client, as: RoleServer
  alias Beethoven.RoleAlloc.Client, as: Client

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
  Starts server as a child of the root supervisor.
  Operation runs from a task to avoid hanging the caller waiting for init.
  (random number between 2.5-5.75 seconds)
  """
  @spec async_timed_start() :: :ok
  def async_timed_start() do
    {:ok, _pid} =
      Task.start(fn ->
        # backoff in milliseconds (random number between 0.25-2.50 seconds)
        :ok = Utils.backoff_n(RoleAlloc.AsyncStart, 10, 0, 250)
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
    #
    # Sets name globally
    :global.re_register_name(__MODULE__, self())
    # Set RoleAlloc role for this node
    :ok = Tracker.add_role(node(), :been_alloc)
    # Subscribe to tracker changes
    {:ok, _node} = Tracker.subscribe()
    #
    Logger.info("Starting Beethoven Role Allocator.")
    roles = Utils.get_role_config()
    Logger.debug(role_alloc_roles: roles)
    #
    Logger.debug("Creating list of roles needed for the cluster.")
    roles_needed = Lib.get_open_roles(roles)
    # convert list to queue
    role_queue = :queue.from_list(roles_needed)
    #
    # Get hosts - sort by hosts held.
    Logger.debug("Creating queue based on node Role load.")
    host_queue = Lib.make_host_queue()
    #
    #
    Logger.info(nodes_found: :queue.len(host_queue), roles_needed: :queue.len(role_queue))
    Logger.debug(host_queue: host_queue, role_queue: role_queue)
    #
    # triggers cleanup job -. Ensures there are no stragglers after a failover
    # Cleanup will trigger an assignment loop
    :ok = Client.start_cleanup()

    # return
    {:ok,
     %{
       role: roles,
       role_queue: role_queue,
       host_queue: host_queue,
       retries: Lib.get_new_retries(roles)
     }}
  end

  #
  #
  #
  # Assignment of roles has hit the max retry threshold
  # Kill assignment loop until change to cluster state
  @impl true
  def handle_cast(:assign, %{
        role: roles,
        role_queue: role_queue,
        host_queue: host_queue,
        retries: {_role_re, total_re, max_role_re, max_tot_re}
      })
      when total_re >= max_tot_re do
    #
    Logger.warning(
      "Beethoven RoleAllocator Server has failed to assign role(s) to the maximum threshold. (#{to_string(max_tot_re)}) retries. Will await change to cluster state."
    )

    {:noreply,
     %{
       role: roles,
       role_queue: role_queue,
       host_queue: host_queue,
       # Reset retries
       retries: {0, 0, max_role_re, max_tot_re}
     }}
  end

  #
  #
  #
  # Assignment of a single role has failed to be assigned to the max threshold.
  # Moves to the next role in the queue
  @impl true
  def handle_cast(:assign, %{
        role: roles,
        role_queue: role_queue,
        host_queue: host_queue,
        retries: {role_re, total_re, max_role_re, max_tot_re}
      })
      when role_re >= max_role_re do
    # get role that is failing to assign
    {{:value, q_role}, new_role_queue} = :queue.out(role_queue)
    # Set role to top of the queue
    new_role_queue = :queue.in(q_role, new_role_queue)
    #
    Logger.warning(
      "Beethoven RoleAllocator Server has failed to assign role (#{to_string(q_role)}) (#{to_string(role_re)}) times. Will move to the next role available and try again"
    )

    # Recurse with next role
    :ok = Client.start_assign()

    {:noreply,
     %{
       role: roles,
       role_queue: new_role_queue,
       host_queue: host_queue,
       # Reset role retries
       retries: {0, total_re, max_role_re, max_tot_re}
     }}
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
        retries: {role_re, total_re, max_role_re, max_tot_re}
      }) do
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
        Logger.info("No more roles to assign. Awaiting changes to cluster state.")

        {:noreply,
         %{
           role: roles,
           role_queue: role_queue,
           host_queue: host_queue,
           # zero out retries
           retries: {0, 0, max_role_re, max_tot_re}
         }}

      #
      # value from queue -> continue on
      {{:value, q_role}, new_role_queue} ->
        Logger.debug("Attempting assignment of role (#{q_role}) to node (#{q_host}).")
        #
        # Check if host is running the desired role
        if Tracker.is_host_running_role?(q_host, q_role) do
          # running role
          Logger.debug("Node (#{q_host}) is already running an instance of role (#{q_role}).")
          # Try again, but with the next host
          new_host_queue = :queue.in(q_host, new_host_queue)
          # Recurse
          :ok = Client.start_assign()
          #
          {:noreply,
           %{
             role: roles,
             role_queue: role_queue,
             host_queue: new_host_queue,
             retries: {role_re + 1, total_re + 1, max_role_re, max_tot_re}
           }}

          #
          #
          # not running role
        else
          Logger.info("Assigning role (#{q_role}) to node (#{q_host}).")
          #
          # Run locally if target server is local
          if q_host == node() do
            # Run locally
            RoleServer.add_role(q_role)
          else
            # Call roleServer in target node to assign the role
            RoleServer.add_role_remote(q_role, q_host)
          end
          # Parse role assignment response
          |> case do
            #
            # Role was assigned
            :assigned ->
              # Write role change to Beethoven.Tracker
              :ok = Tracker.add_role(q_host, q_role)
              Logger.info("Successfully assigned role (#{q_role}) to node (#{q_host}).")
              # Add host to back of the queue
              new_host_queue = :queue.in(q_host, new_host_queue)
              # Recurse
              :ok = Client.start_assign()
              #
              {:noreply,
               %{
                 role: roles,
                 role_queue: new_role_queue,
                 host_queue: new_host_queue,
                 # reset role retries
                 retries: {0, total_re, max_role_re, max_tot_re}
               }}

            #
            #
            # Remote assignment timed out
            {:error, :timeout} ->
              Logger.alert("Role assignment for role (#{q_role}) on node (#{q_host}) timed out.")
              # Add host to back of the queue
              new_host_queue = :queue.in(q_host, new_host_queue)
              # Recurse - try on another host
              :ok = Client.start_assign()
              #
              {:noreply,
               %{
                 role: roles,
                 role_queue: role_queue,
                 host_queue: new_host_queue,
                 retries: {role_re + 1, total_re + 1, max_role_re, max_tot_re}
               }}

            #
            #
            # Catch all for all other errors
            {:error, msg} ->
              Logger.error(
                "RoleServer on node (#{q_host}) failed to create instance of role (#{q_role}). [#{msg}]"
              )

              # Add host to back of the queue
              new_host_queue = :queue.in(q_host, new_host_queue)
              # Recurse - try on another host
              :ok = Client.start_assign()
              #
              {:noreply,
               %{
                 role: roles,
                 role_queue: role_queue,
                 host_queue: new_host_queue,
                 retries: {role_re + 1, total_re + 1, max_role_re, max_tot_re}
               }}
          end
        end
    end
  end

  #
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
        retries: {_role_re, _total_re, _max_role_re, _max_tot_re}
      }) do
    Logger.info("Beethoven Role Allocator clean-up job triggered.")
    # clean up offline nodes -> returns roles removed from the nodes.
    removed_roles = Tracker.clear_offline_roles()

    Logger.info(
      "(#{length(removed_roles)}) role(s) have been cleared from the Tracker for reassignment."
    )

    #
    # Uses roles held in state and creates a new queue from scratch
    # based on roles needed on the tracker
    Logger.debug("Creating list of roles needed for the cluster.")
    roles_needed = Lib.get_open_roles(roles)
    # convert list to queue
    new_role_queue = :queue.from_list(roles_needed)
    #
    # Make new host_queue
    new_host_queue = Lib.make_host_queue()
    #
    # Count diffs
    host_diff = :queue.len(new_host_queue) - :queue.len(host_queue)
    role_diff = :queue.len(new_role_queue) - :queue.len(role_queue)
    #
    Logger.info(
      "Clean up job completed. Changes: [(#{to_string(host_diff)}) Node(s)] | [(#{to_string(role_diff)}) Role(s)]"
    )

    #
    Logger.debug(new: {new_host_queue, new_role_queue}, old: {host_queue, role_queue})

    # triggers assignment loop
    :ok = Client.start_assign()

    {:noreply,
     %{
       role: roles,
       role_queue: new_role_queue,
       host_queue: new_host_queue,
       # reset retries
       retries: Lib.get_new_retries(roles)
     }}
  end

  #
  #
  #
  # Call to RoleAlloc server to let it know a node is going down.
  # This allows RoleAlloc server to move the roles prior to the expected outage.
  # Uses Handle_info so it can respond to calls from other nodes.
  def handle_info({:prune, seed, caller, nodeName}, state) do
    #
    # Change node to offline so other nodes stop monitoring it.
    :ok = Tracker.set_node_offline(nodeName)
    #
    # No need to trigger cleanup as the change to tracker will cause a Mnesia event for the same
    #
    # respond to caller
    _ = send(caller, {:prune, seed, :ok})
    #
    # If this node is to be pruned, kill role Alloc
    # This prevents service to continuing
    if nodeName == node() do
      exit("RoleAlloc Server killed via Self-Prune request.")
    end

    #
    {:noreply, state}
  end

  #
  #
  # handles Mnesia table update events.
  # Redirects to RoleAlloc.MnesiaNotify module
  @impl true
  def handle_info({:mnesia_table_event, msg}, %{
        role: roles,
        role_queue: role_queue,
        host_queue: host_queue,
        retries: retry_tup
      }) do
    #
    {:ok, new_host_queue, retry_tup} = MnesiaNotify.run(msg, roles, host_queue, retry_tup)

    {:noreply,
     %{
       role: roles,
       role_queue: role_queue,
       host_queue: new_host_queue,
       retries: retry_tup
     }}
  end

  #
  #
  #
end
