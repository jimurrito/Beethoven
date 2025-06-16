defmodule Beethoven.RoleServer do
  @moduledoc """
  # DEPRECATED! Do not use. Use `Beethoven.RoleMgmt` instead.

  This server is responsible for the management and allocation of specialized OTP complaint PIDs.
  Roles are defined in in the application config for `:beethoven`.

  ## Example

      config :beethoven,
        ...
        roles: [
          # {<AtomName>, <Module>, <Initial Args>, <InstanceCount>}
          {:test, Beethoven.TestRole, [arg1: "arg1"], 1}
        ]

  Based on the definition for each role, the nodes in the `Beethoven` cluster will ensure the required amount of that service is running across the cluster.
  The number of service instances needed for the role is defined with the `InstanceCount` element in the tuple. These services are spread across the cluster.

  """
  require Logger
  alias Beethoven.CoreServer
  alias Beethoven.Utils
  alias Beethoven.DistrServer
  alias Beethoven.Signals

  use DistrServer, subscribe?: false
  use CoreServer

  alias __MODULE__.Tracker, as: RoleTracker

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Types
  #

  #
  #
  @typedoc """
  Simplified type for tracker records.
  Just excludes the table name from the record tuple.
  """
  @type roleRecord() ::
          {roleName :: atom(), roleModule :: module(), args :: any(), instances :: integer()}
  #
  #
  @typedoc """
  Role list in the form of a map.
  """
  @type roleMap() :: map()

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # DistrServer callback functions
  #

  #
  #
  @doc """
  Supervisor Entry point.
  """
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(init_args \\ []) do
    DistrServer.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  #
  #
  @impl true
  def config() do
    %{
      tableName: RoleTracker,
      columns: [:role, :count, :assigned, :workers, :last_change],
      indexes: [],
      dataType: :ordered_set,
      copyType: :multi
    }
  end

  #
  # Setup table with all the roles defined in `config.exs`
  @impl true
  def create_action(_tableConfig) do
    # fn to setup table with initial data
    {:atomic, :ok} =
      fn ->
        # Get Roles from config
        get_role_config()
        |> Enum.each(
          # Add roles to table
          fn {name, {_mod, _args, inst}} ->
            # {MNESIA_TABLE, role_name, count, assigned, workers, last_changed}
            :mnesia.write({RoleTracker, name, inst, 0, [], DateTime.now!("Etc/UTC")})
          end
        )
      end
      |> :mnesia.transaction()

    :ok
  end

  #
  #
  @impl true
  def entry_point(_var) do
    Logger.info(status: :startup)
    # get roles from config.exs
    role_map = get_role_config()
    # Start DynamicSupervisor
    {:ok, _pid} = DynamicSupervisor.start_link(name: Beethoven.RoleSupervisor)
    # Subscribe to node change updates from CoreServer
    :ok = alert_me()
    # Start assign loop
    :ok = start_assign()
    #
    Logger.info(status: :startup_complete)
    {:ok, role_map}
  end

  #
  #
  # handles assign cast.
  # When triggered, RoleServer will attempt to assign itself work after a backoff.
  # Use `start_assign/0` for casts to this callback.
  @impl true
  def handle_cast(:assign, role_map) do
    Logger.info(operation: :assign, status: :startup)
    # backoff bases on config
    {:ok, backoff} =
      Utils.get_app_env(:common_random_backoff, 150..300)
      |> Utils.random_backoff()

    Logger.debug(operation: :assign_backoff_complete, waited_ms: backoff)

    # Assign self a job (if applicable)
    assign()
    # create role on server
    |> case do
      # No work
      :noop ->
        Logger.info(operation: :assign, status: :no_work)

        #
        {:noreply, role_map}

      # heres a job!
      {:ok, roleName} ->
        Logger.info(operation: :assign, status: :found_work, work: roleName)
        # Start role
        :ok = start_role(roleName, role_map)
        # Restart assign loop
        :ok = start_assign()
        Logger.info(operation: :assign, status: :ok, work: roleName)
        {:noreply, role_map}
    end
  end

  #
  #
  # [Callback] handles node_update cast from CoreServer
  # triggered when a node in the cluster changes state.
  @impl true
  def handle_cast({:node_update, nodeName, status}, state) do
    Logger.info(operation: :node_update, status: :startup, node: nodeName, status: status)
    #
    case status do
      # Node has come online -> ignore
      :online ->
        #
        Logger.info(operation: :node_update, status: :ok, node: nodeName, status: status)

      # Node has gone offline -> prune node
      :offline ->
        # backoff bases on config
        {:ok, backoff} =
          Utils.get_app_env(:common_random_backoff, 150..300)
          |> Utils.random_backoff()

        Logger.debug(operation: :node_update_backoff_complete, waited_ms: backoff)

        # remove node from table
        :ok = prune_node(nodeName)
        # Trigger assign
        :ok = start_assign()
        #
        Logger.info(operation: :node_update, status: :pruned, node: nodeName, status: status)
    end

    #
    #
    {:noreply, state}
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Public API functions
  #

  #
  #
  @doc """
  Starts assignment job on the RoleServer.
  """
  @spec start_assign() :: :ok
  def start_assign() do
    DistrServer.cast(__MODULE__, :assign)
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Internal Role utils functions
  #

  #
  #
  #
  #
  @doc """
  Retrieves roles from config and converts to map.
  """
  @spec get_role_config() :: roleMap()
  def get_role_config() do
    # get roles from config.exs
    Utils.get_app_env(:roles, [])
    # converts to map
    |> role_list_to_map()
  end

  #
  #
  #
  @doc """
  Creates a map from a list of maps. First element of the map needs to be an atom.
  This same atom will be the key for the rest of the data in the map.
  """
  @spec role_list_to_map([roleRecord()]) :: roleMap()
  def role_list_to_map(role_list) do
    role_list_to_map(role_list, %{})
  end

  # End loop
  defp role_list_to_map([], state) do
    state
  end

  # Working loop
  defp role_list_to_map([{role_name, mod, args, inst} | role_list], state)
       when is_atom(role_name) do
    state = state |> Map.put(role_name, {mod, args, inst})
    role_list_to_map(role_list, state)
  end

  # Working loop - bad syntax for role manifest
  defp role_list_to_map([role_bad | role_list], state) do
    Logger.error(
      "One of the roles provided is not in the proper syntax. This role will be ignored.",
      expected: "{:role_name, Module, ['args'], 1}",
      received: role_bad
    )

    role_list_to_map(role_list, state)
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Internal Lib functions
  #

  #
  #
  @doc """
  Manually copy the tracking DB to the node.
  """
  @spec copy_tracker() :: :ok | :already_exists | {:error, any()}
  def copy_tracker() do
    copy_table(RoleTracker)
  end

  #
  #
  # Start a role under the dynamic role supervisor
  # role_name, {mod, args, inst}
  @spec start_role(atom(), roleMap()) :: :ok
  defp start_role(roleName, roleMap) do
    # Parse role info from state
    {mod, args, _inst} = Map.get(roleMap, roleName)
    # Add role to role supervisor
    {:ok, _pid} = DynamicSupervisor.start_child(Beethoven.RoleSupervisor, {mod, args})
    # Send signal
    Signals.increment_beethoven_role_count()
  end

  #
  #
  # Assignment function
  @spec assign() :: {:ok, atom()} | :noop
  defp assign() do
    #
    fn ->
      # Acquire locks
      _ = :mnesia.lock_table(RoleTracker, :read)
      _ = :mnesia.lock_table(RoleTracker, :write)
      # Find work on the table - pick random work
      find_work()
      |> case do
        # No work found
        [] ->
          :noop

        # work found
        work ->
          # pick random role, expand object
          [role_name, count, assigned, workers, _last_changed] = work |> Enum.random()
          # increment assigned and add self to workers
          :ok =
            :mnesia.write({
              RoleTracker,
              role_name,
              count,
              assigned + 1,
              [node() | workers],
              DateTime.now!("Etc/UTC")
            })

          # return role
          {:ok, role_name}
      end

      #
    end
    #
    |> :mnesia.transaction()
    # Unwrap {:atomic, atom() | :noop}
    |> elem(1)
  end

  #
  #
  # Finds jobs that are not completely fulfilled yet.
  @spec find_work() :: [roleRecord()]
  defp find_work() do
    fn ->
      :mnesia.select(RoleTracker, [
        {
          {RoleTracker, :"$1", :"$2", :"$3", :"$4", :"$5"},
          # Finds records where :count is larger then :assigned.
          [{:>, :"$2", :"$3"}],
          [:"$$"]
        }
      ])
    end
    |> :mnesia.transaction()
    # Unwrap {:atomic, records}
    |> elem(1)
    |> Enum.filter(
      # Filter out roles that we already host
      fn [_role_name, _count, _assigned, workers, _last_changed] ->
        not Enum.member?(workers, node())
      end
    )
  end

  #
  #
  # Clears work from a given node
  @spec prune_node(node()) :: :ok
  defp prune_node(nodeName) do
    # transaction function
    fn ->
      # Acquire locks
      _ = :mnesia.lock_table(RoleTracker, :read)
      _ = :mnesia.lock_table(RoleTracker, :write)
      # iterates all rows and removes the downed node.
      :mnesia.foldl(
        fn record, _acc -> clear_node(record, nodeName) end,
        :ok,
        RoleTracker
      )
    end
    |> :mnesia.transaction()
    |> elem(1)
  end

  #
  #
  # Clears node from role records.
  @spec clear_node(
          {RoleTracker, atom(), integer(), integer(), list(node()), DateTime},
          node()
        ) ::
          :ok
  defp clear_node({RoleTracker, role, count, assigned, workers, _last_changed}, nodeName) do
    if Enum.member?(workers, nodeName) do
      :ok =
        :mnesia.write({
          RoleTracker,
          role,
          count,
          assigned - 1,
          List.delete(workers, nodeName),
          DateTime.now!("Etc/UTC")
        })
    end

    # return :ok
    :ok
    #
  end

  #
  #
end
