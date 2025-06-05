defmodule Beethoven.RoleServer do
  @moduledoc """
  Server PID that manages role assignment across the cluster.
  Leveraging the Mnesia integration with `DistrServer`,
  these processes will be ephemeral and keep all state within Mnesia.
  """
  require Logger
  alias Beethoven.Utils
  alias Beethoven.CoreServer
  alias Beethoven.DistrServer
  alias Beethoven.RoleUtils

  use DistrServer, subscribe?: false

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Types
  #

  #
  @typedoc """
  Alias for `atom()`.
  """
  @type roleName :: atom()

  #
  @typedoc """
  Simplified type for tracker records.
  Just excludes the table name from the record tuple.
  """
  @type roleRecord() ::
          {roleName :: atom(), roleModule :: module(), args :: any(), instances :: integer()}
  #
  @typedoc """
  List of `roleRecord()` objects.
  """
  @type roleRecords() :: list(roleRecord())
  #

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
      tableName: __MODULE__.Tracker,
      columns: [:role, :count, :assigned, :workers, :last_change],
      indexes: [],
      dataType: :ordered_set,
      copyType: :multi
    }
  end

  #
  # Setup table with all the roles defined in `config.exs`
  @impl true
  def create_action({tableName, _columns, _indexes, _dataType, _copyType}) do
    # fn to setup table with initial data
    {:atomic, :ok} =
      fn ->
        # Get Roles from config
        RoleUtils.get_role_config()
        |> Enum.each(
          # Add roles to table
          fn {name, {_mod, _args, inst}} ->
            # {MNESIA_TABLE, role_name, count, assigned, workers, last_changed}
            :mnesia.write({tableName, name, inst, 0, [], DateTime.now!("Etc/UTC")})
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
    role_map = RoleUtils.get_role_config()
    # Start DynamicSupervisor
    {:ok, _pid} = DynamicSupervisor.start_link(name: Beethoven.RoleSupervisor)
    # Subscribe to node change updates from CoreServer
    :ok = CoreServer.alert_me(__MODULE__)
    # Start assign loop
    :ok = start_assign()
    #
    Logger.info(status: :startup_complete)
    {:ok, role_map}
  end

  #
  #
  #
  # Called by CoreServer when a node changes state or gets added to the cluster
  @impl true
  def node_update(nodeName, status) do
    DistrServer.cast(__MODULE__, {:node_update, nodeName, status})
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

        # get DistrServer Mnesia config
        config = config()
        # remove node from table
        :ok = prune_node(config.tableName, nodeName)
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
  # Client functions
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
  # Internal Lib functions
  #

  #
  #
  @doc """
  Manually copy the tracking DB to the node.
  """
  @spec copy_tracker() :: :ok | :already_exists | {:error, any()}
  def copy_tracker() do
    config = config()
    copy_table(config.tableName)
  end

  #
  #
  # Start a role under the dynamic role supervisor
  # role_name, {mod, args, inst}
  @spec start_role(roleName(), RoleUtils.roleMap()) :: :ok
  defp start_role(roleName, roleMap) do
    #
    IO.inspect({:DEBUG, roleMap, roleName})
    # Parse role info from state
    {mod, args, _inst} = Map.get(roleMap, roleName)
    # Add role to role supervisor
    {:ok, _pid} = DynamicSupervisor.start_child(Beethoven.RoleSupervisor, {mod, args})
    #
    :ok
  end

  #
  #
  # Assignment function
  @spec assign() :: {:ok, roleName()} | :noop
  defp assign() do
    # get DistrServer Mnesia config
    config = config()
    #
    fn ->
      # Acquire locks
      _ = :mnesia.lock_table(config.tableName, :read)
      _ = :mnesia.lock_table(config.tableName, :write)
      # Find work on the table - pick random work
      find_work(config.tableName)
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
              config.tableName,
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
    # Unwrap {:atomic, roleName() | :noop}
    |> elem(1)
  end

  #
  #
  # Finds jobs that are not completely fulfilled yet.
  @spec find_work(atom()) :: roleRecords()
  defp find_work(tableName) do
    fn ->
      :mnesia.select(tableName, [
        {
          {tableName, :"$1", :"$2", :"$3", :"$4", :"$5"},
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
  @spec prune_node(atom(), node()) :: :ok
  defp prune_node(tableName, nodeName) do
    # transaction function
    fn ->
      # Acquire locks
      _ = :mnesia.lock_table(tableName, :read)
      _ = :mnesia.lock_table(tableName, :write)
      # iterates all rows and removes the downed node.
      :mnesia.foldl(
        fn record, _acc -> clear_node(record, nodeName) end,
        :ok,
        tableName
      )
    end
    |> :mnesia.transaction()
    |> elem(1)
  end

  #
  #
  # Clears node from role records.
  @spec clear_node({atom(), roleName(), integer(), integer(), list(node()), DateTime}, node()) ::
          :ok
  defp clear_node({tableName, role, count, assigned, workers, _last_changed}, nodeName) do
    if Enum.member?(workers, nodeName) do
      :ok =
        :mnesia.write({
          tableName,
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
