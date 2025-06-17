defmodule Beethoven.RoleMgmt.Assign do
  @moduledoc """
  Server to track nodes and their role assignments.
  Once boot, the service will assign one of each open roles to itself.
  These roles are cast to the `Manager` service to spawn the roles.

  Failover of roles across the cluster is handled by the `Failover` service.

  """

  alias Beethoven.RoleMgmt.Manager
  alias Beethoven.RoleMgmt.Utils
  alias Beethoven.DistrServer

  require Logger
  use DistrServer, subscribe?: true

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Types
  #

  #
  @typedoc """
  Represents a single record in the Mnesia table.
  """
  @type record() ::
          {table :: module(), role :: atom(), count :: integer(), assigned :: integer(),
           workers :: list(atom()), last_changed :: DateTime.t()}

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
      # :mnesia data types
      dataType: :ordered_set,
      # :local | :multi
      copyType: :multi
    }
  end

  #
  #
  # Setup table with all the roles defined in `config.exs`
  @impl true
  def create_action({_tableName, _columns, _indexes, _dataType, _copyType}) do
    # fn to setup table with initial data
    fn ->
      # Get Roles from config
      Utils.get_role_config()
      |> Enum.each(
        # Add roles to table
        fn {name, {_mod, _args, inst}} ->
          # {MNESIA_TABLE, role_name, count, assigned, workers, last_changed}
          :mnesia.write({get_table_name(), name, inst, 0, [], DateTime.now!("Etc/UTC")})
        end
      )
    end
    |> :mnesia.transaction()
    |> elem(1)
  end

  #
  #
  @impl true
  def entry_point(_var) do
    Logger.info(status: :startup_complete)
    # start the initial assign loop
    {:ok, Utils.get_role_config(), {:continue, :assign}}
  end

  #
  #
  # Assign loop handlers
  @impl true
  def handle_continue(:assign, roleMap) do
    Logger.debug(operation: :assign, status: :startup)
    tableName = get_table_name()
    # Lock table and perform logic
    :ok =
      fn ->
        #
        # Acquire locks
        _ = :mnesia.lock_table(tableName, :read)
        _ = :mnesia.lock_table(tableName, :write)
        #
        # Get roles that are not at capacity
        :mnesia.select(tableName, [
          {
            {tableName, :_, :"$1", :"$2", :_, :_},
            [
              # when count is larger then assigned
              {:>, :"$1", :"$2"}
            ],
            [:"$_"]
          }
        ])
        #
        # Check result from Mnesia
        |> case do
          # nothing found -> no work, zug zug
          [] ->
            Logger.info(operation: :assign, status: :no_work)

          # records are found
          roles ->
            #
            roles
            |> Enum.each(fn {^tableName, role, count, _assigned, workers, _lc} ->
              #
              # make new list of workers
              new_workers = [node() | workers]
              #
              Logger.info(operation: :assign, status: :assign_to_self, role: role)
              #
              # write change to mnesia
              :mnesia.write(
                {tableName, role, count, length(new_workers), new_workers,
                 DateTime.now!("Etc/UTC")}
              )
            end)
        end
      end
      |> :mnesia.transaction()
      |> elem(1)

    #
    {:noreply, roleMap}
  end

  #
  #
  # Handle updates from Mnesia
  # Once a node fails over, `Failover` will prune the node from the table and assign a new host based on the `Beethoven.Allocator`.
  # this handler will screen all updates to the table and blindly cast updates to `Manager` for assignment.
  # `Manager` will handle de-duplication of roles.
  @impl true
  def handle_info(
        {:mnesia_table_event,
         {_opt_type, RoleTracker, {RoleTracker, role, _count, _assigned, workers, _lc}, _previous,
          _op_data}},
        roleMap
      ) do
    #
    # Check if this node is a worker on the update
    # If so, attempt to spawn the role on the manager.
    if Enum.member?(workers, node()) do
      {mod, args, _int} = Map.get(roleMap, role)
      :ok = Manager.add_role(role, mod, args)
    end

    #
    {:noreply, roleMap}
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Public API functions
  #

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Internal functions
  #

  #
  #
end
