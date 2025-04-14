defmodule Beethoven.CoreServer do
  @moduledoc """
  Core Service for Beethoven.
  Watches other nodes within the cluster and cascade updates across the beethoven PIDs as needed.

  Once the server is started, it will spawn downlevel servers needed by Beethoven.
  - `RoleServer`
  - `BeaconServer`

  ---

  # External API calls
  These are calls that can be made from external servers
  - `alert_me/1` -> Alerts the caller on cluster node changes. (see 'Listening for cluster node changes' for more info.)
  - `new_node/1` -> Adds node to CoreServer state mnesia table. (Should be called by the `Listener` server)
  - `get_mode/0` -> Returns the mode of the CoreServer. (:standalone | :clustered)

  ---

  # Listening for cluster node changes
  Using `alert_me/1` from a local client, you can tell the CoreServer to call you back when there is a change to a cluster node.
  Ignores changes to itself, only delivers updates of other nodes.

  To use this, the caller *must* implement the `CoreServer` behavior and callback `node_down/2`.
  Once a change occurs, the CoreServer will call the callback function for the following module/process.
  `node_down/2` should contain the logic needed when a node changes state.

  """

  alias Beethoven.Utils
  alias Beethoven.MnesiaTools
  alias Beethoven.DistrServer

  require Logger
  use DistrServer

  #
  #
  # Callbacks
  #

  @doc """
  Callback needed for downlevel services to streamline receiving node down updates.
  **Required if you follow core server for cluster updates via `alert_me/1`**
  """
  @callback node_update(nodeName :: node(), status :: nodeStatus()) :: :ok
  #

  #
  #
  # Types
  #
  @typedoc """
  Possible status(s) for nodes within Beethoven.
  # Options
  - `:online`
  - `:offline`
  """
  @type nodeStatus() :: :online | :offline

  #
  #
  @typedoc """
  Possible statuses for CoreServer
  """
  @type serverStatus() :: :standalone | :clustered

  #
  #
  @typedoc """
  A single row in the CoreServer tracker.
  """
  @type trackerRow() ::
          {mod :: module(), nodeName :: node(), status :: nodeStatus(), lastChange :: DateTime}

  #
  #
  @typedoc """
  Single tracker event from the Mnesia table
  """
  @type trackerEvent() ::
          {opType :: :write | :delete, mod :: module(), new_row :: trackerRow(),
           old_rows :: list(trackerRow()), pid_struct :: any()}

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
  @spec start_link(serverStatus()) :: GenServer.on_start()
  def start_link(init_args) do
    DistrServer.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  #
  # Mnesia config callback
  @impl true
  def config() do
    %{
      tableName: __MODULE__.Tracker,
      columns: [:node, :status, :last_change],
      indexes: [:node],
      dataType: :ordered_set,
      copyType: :multi,
      subscribe?: true
    }
  end

  #
  #
  @impl true
  # Not used for this PID, so we want to return :ok
  def create_action(_tableConfig) do
    :ok
  end

  #
  #
  @doc """
  Callback for entry when we are in :standalone or :clustered mode
  """
  @impl true
  def entry_point(mode) do
    tableConfig = config() |> DistrServer.distr_to_table_conf()
    # Add self to tracker
    :ok = add_self(tableConfig)
    #
    Logger.info(table: elem(tableConfig, 0), mode: mode, status: :startup)
    #
    # Add servers to root supervisor
    :ok = start_downlevel_servers()
    #
    # Return mode + empty list of alert followers.
    {:ok, {mode, []}}
  end

  #
  #
  @doc """
  Callback to handle casts for services that need updates on node state.
  """
  @impl true
  def handle_cast({:alert_me, nodeName}, {mode, followers}) do
    followers = [nodeName | followers]

    Logger.info(operation: :alert_me, new_follower: nodeName, follower_count: length(followers))
    # Add caller node name to followers list
    {:noreply, {mode, [nodeName | followers]}}
  end

  #
  #
  # Provides caller with status on cluster.
  # Options:
  # - `:standalone`
  # - `:clustered`
  # Use `get_mode/1` for external calls.
  @impl true
  def handle_call(:get_mode, _from, {mode, followers}) do
    Logger.debug(operation: :get_mode, mode: mode)
    {:reply, mode, {mode, followers}}
  end

  #
  #
  # Callback when the local Locator server has received a node that should be tracked.
  # Use `new_node/1` for external calls.
  @impl true
  def handle_call({:add_node, nodeName}, _from, {mode, followers}) do
    Logger.info(operation: :add_node, new_node: nodeName, mode: mode)
    tableConfig = config() |> DistrServer.distr_to_table_conf()
    :ok = add_node(tableConfig, nodeName)
    {:reply, :ok, {mode, followers}}
  end

  #
  #
  # Callback for node fault updates.
  # This callback is triggered when a monitored node goes down.
  # Attempts to update the node in Mnesia
  @impl true
  def handle_info({:nodedown, nodeName}, {mode, followers}) do
    Logger.warning(operation: :nodedown, affected_node: nodeName, mode: mode)

    {tableName, _columns, _indexes, _dataType, _copyType} =
      config() |> DistrServer.distr_to_table_conf()

    # random backoff to reduce noise on Mnesia (15ms - 750ms)
    :ok = Utils.backoff_n(__MODULE__, 50, 1, 15)
    # Attempt to update Mnesia
    :ok = update_node(tableName, nodeName, :offline)
    #
    {:noreply, {mode, followers}}
  end

  #
  #
  # Handles when a node on the tracker changes state.
  # Specifically when a node is new, or goes from `:offline` to `:online`.
  # Offline changes happen via `:nodedown` + `handle_info/2`
  @impl true
  def handle_info({:mnesia_table_event, msg}, {_mode, followers}) do
    {nodeName, status, mode} =
      msg
      |> mnesia_notify()
      |> case do
        # node on tracker is now `:online`
        {nodeName, :online} ->
          # set server to `:clustered`
          # monitor node
          true = Node.monitor(nodeName, true)
          {nodeName, :online, :clustered}

        # Node goes `:offline` -> do nothing
        {nodeName, :offline} ->
          # unmonitor node
          true = Node.monitor(nodeName, false)
          #
          # determine if we need to become :standalone
          mode =
            if Node.list() == [] do
              # No more other nodes -> standalone
              :standalone
            else
              # Other nodes still available -> :clustered
              :clustered
            end

          #
          {nodeName, :offline, mode}
      end

    #
    Logger.debug(
      operation: :mnesia_table_event,
      affected_node: nodeName,
      node_status: status,
      mode: mode
    )

    # Alert followers
    :ok = alert_followers(nodeName, status, followers)

    #
    {:noreply, {mode, followers}}
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Client functions
  #

  #
  #
  @doc """
  Tell the local CoreServer that we want to be alerted to changes to cluster node state.
  """
  @spec alert_me(module()) :: :ok
  def alert_me(module_name) do
    DistrServer.cast(__MODULE__, {:alert_me, module_name})
  end

  #
  #
  @doc """
  Add a node to the Cluster Node tracker.
  If node is already tracked, it will be marked as `:online`.
  """
  @spec new_node(node()) :: :ok
  def new_node(nodeName) do
    DistrServer.call(__MODULE__, {:add_node, nodeName})
  end

  #
  #
  @doc """
  Gets mode from the CoreServer.
  """
  @spec get_mode() :: serverStatus()
  def get_mode() do
    DistrServer.call(__MODULE__, :get_mode)
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Internal Lib functions
  #

  #
  #
  # Downlevel servers
  # Servers *must* be OTP compliant.
  @spec downlevel_servers() :: list(module())
  defp downlevel_servers() do
    [
      Beethoven.RoleServer
    ]
  end

  #
  #
  # Starts downlevel servers
  @spec start_downlevel_servers() :: :ok
  defp start_downlevel_servers() do
    downlevel_servers()
    |> Enum.each(&({:ok, _pid} = Supervisor.start_child(Beethoven.RootSupervisor, &1)))
  end

  #
  #
  # Alert followers
  # Follower *MUST* implement CoreServer behavior
  @spec alert_followers(node(), nodeStatus(), list(module())) :: :ok
  defp alert_followers(nodeName, status, followers) do
    followers
    |> Enum.each(&(:ok = &1.node_update(nodeName, status)))
  end

  #
  #
  # Add a node to tracker as online.
  # There is no mechanism to remove the node from the tracker.
  @spec add_node(MnesiaTools.tableConfig(), node()) :: :ok
  defp add_node({tableName, _columns, _indexes, _dataType, _copyType}, nodeName) do
    fn ->
      :mnesia.write({tableName, nodeName, :online, DateTime.now!("Etc/UTC")})
    end
    |> :mnesia.transaction()
    # unwrap {:atomic, :ok} -> :ok
    |> elem(1)
  end

  #
  #
  # Add self to tracker as online.msg, state
  @spec add_self(MnesiaTools.tableConfig()) :: :ok
  defp add_self(tableConfig) do
    add_node(tableConfig, node())
  end

  #
  #
  # Change status of a node on the tracker
  @spec update_node(atom(), node(), nodeStatus()) :: :ok
  defp update_node(tableName, nodeName, new_status) do
    fn ->
      # read the status of the node to ensure it is not already updated on the table.
      # wread/1 ensures we get a `:write` lock on the record when we read it.
      [{tableName, ^nodeName, old_status, _last_change}] =
        :mnesia.wread({tableName, nodeName})

      # check status is *not* the desired one.
      :ok =
        if old_status != new_status do
          # write change to mnesia
          :mnesia.write({tableName, nodeName, new_status, DateTime.now!("Etc/UTC")})
        else
          # ignore as the change was already committed to the table.
          :ok
        end

      # return :ok
      :ok
    end
    |> :mnesia.transaction()
    # unwrap {:atomic, :ok} -> :ok
    |> elem(1)
  end

  #
  #
  @spec mnesia_notify(trackerEvent()) :: {node(), nodeStatus()}
  defp mnesia_notify(msg) do
    msg
    |> case do
      # New node was added to the table
      {:write, _, {_, nodeName, :online, _}, [], _}
      when nodeName != node() ->
        {nodeName, :online}

      # Existing node goes from `:offline` to `:online`.
      {:write, _, {_, nodeName, :online, _}, [{_, nodeName, :offline, _}], _}
      when nodeName != node() ->
        {nodeName, :online}

      # Existing node goes from `:online` to `:offline`.
      {:write, _, {_, nodeName, :offline, _}, [{_, nodeName, :online, _}], _}
      when nodeName != node() ->
        {nodeName, :offline}
    end
  end

  #
  #
end
