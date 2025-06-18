defmodule Beethoven do
  @moduledoc """
  A Decentralized failover and peer-to-peer node finding framework for Elixir.
  Using a TCP socket, Elixir nodes running Beethoven can find each other within a pre-defined network range.

  # Public API

  - `ready?/0` -> Returns true if Beethoven has fully initialized. False if not.
      Fully initialized is determined when the RoleMgmt Assigns server.

  - `until_ready/1` -> Holds the thread until Beethoven has fully initialized, or provided timeout value has become exhausted.
      Default timeout value is `5_000` milliseconds.

  - `get_node_status/0` -> Returns the status of the node within the Beethoven cluster.
      Possible returns are: `:standalone` & `:clustered`.

  - `get_cluster_nodes/0` -> Returns a list of all the nodes have have joined the Beethoven cluster.

  - `get_active_cluster_nodes/0` -> Similar to `get_cluster_nodes/0`, but only provides nodes that are active/online.

  - `get_detailed_cluster_nodes/0` -> Detailed list of all the nodes that have joined the Beethoven cluster + associated metadata.

  - `get_roles/0` -> Returns all Beethoven hosted roles with their associated metadata.

  - `whois_hosting/0` -> Looks up, and returns a list of nodes that host a given Beethoven role.

  - `allocate/0` -> Wrapper for `Beethoven.Allocator.allocate/0`.

  ---

  # Architecture

  Beethoven is made of multiple smaller services that provide a depth of failover and loadbalancing functionality.

  ## `CoreServer`

  Monitors nodes in the Mnesia cluster.
  The server provides a behaviour that allows for PIDs to request a callback in the event of a node status change.
  The callback is called `alert_me/0`. This function is available to any module using `CoreServer`.
  Once used, the caller will be sent a GenServer cast containing the updated information.

      {:node_update, {nodeName, status}}

  Where status can be `:offline` or `:online`, and nodeName is the URI of the node.
  CoreServer manages the monitoring and de-monitoring nodes in Beethoven as they go through their lifecycle.

  ---

  ## `RoleMgmt`

  A framework for distributing work across a Beethoven cluster.
  Roles are defined in the `:beethoven` application configuration.
  These roles are hosted on the nodes that come into the cluster, and redistributed when they fail.

  For more information on using RoleMgmt, please see the module's documentation.

  ---

  ## `Allocator`

  A signal based work allocator that helps determine how busy a given Beethoven cluster node is.
  Using these signals, it determines how busy a node is, and assigns a float.
  The smaller the float, the less busy a node is considered.

  Using `Beethoven.Allocator.Agent`, you gain access to the `signal()` macro.

      signal(name: :http_connections, weight: 10.0, type: :count)

  This allows you to create your own signals to feed into the allocator.
  This method allows the allocator to be flexible, and signals to be declared and used as needed.

  Calling `Beethoven.Allocator.allocate/0` will check the Mnesia table used by the Allocator, and return the lest-busy node.

  ---

  ## `BeaconServer`

  This PID runs a TCP-Socket server to help new Beethoven nodes find each other.
  The port for listener can be set in the application configuration for `Beethoven`.
  Using this port, the `Locator` service within the other nodes can attempt to find each other.

  This module utilizes `Beethoven.SeekChat` for (de)serialization of TCP calls.

  ---

  ## `Locator`

  This PID will enumerate all IPs within a given subnet; checking if they are running an instance of `BeaconServer`.
  This PID will enumerate the IPs 3 times.
  If nothing is found after the 3rd attempt, the cluster start as-is in :standalone mode.

  This module utilizes `Beethoven.SeekChat` for (de)serialization of TCP calls.

  ---

  ## `HwMon`

  Set of PIDs to monitor and record historical hardware consumption.
  Will sample CPU and RAM usage every 5 seconds and save up to 100k samples per metric.
  When resources are sampled, a signal to `Allocator` is called and the utilization is logged.

  """

  alias Beethoven.Allocator
  alias Beethoven.CoreServer
  alias Beethoven.RoleMgmt.Assign, as: RoleServer

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Types
  #

  #
  @typedoc """
  List of node names.
  """
  @type nodeList() :: list(node())

  #
  @typedoc """
  Status of a Beethoven cluster node.
  """
  @type nodeStatusMap() :: %{
          node: node(),
          status: CoreServer.nodeStatus(),
          last_change: DateTime.t()
        }

  #
  @typedoc """
  List of `nodeStatus()` objects.
  """
  @type nodeStatusMapList :: list(nodeStatusMap())

  #
  @typedoc """
  Role data structure.
  """
  @type role_definition() :: %{
          role: atom(),
          count: integer(),
          assigned: integer(),
          nodes: nodeList()
        }

  #
  @typedoc """
  List of `role()`.
  """
  @type roleDefinitionList() :: list(role_definition())

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Holistic external client API for Beethoven.
  #

  #
  #
  @doc """
  Gets the current ready state for Beethoven.

  Wrapper for `Beethoven.Ready.ready?/0`.
  """
  @spec ready?() :: boolean()
  def ready?() do
    Beethoven.Ready.ready?()
  end

  #
  #
  @doc """
  Similar to `ready?()` but will block until the service is ready.
  Defaults to 5_000 milliseconds.

  Wrapper for `Beethoven.Ready.until_ready/1`.
  """
  @spec until_ready(integer()) :: :ok | :timeout
  def until_ready(timeout \\ 5_000) do
    Beethoven.Ready.until_ready(timeout)
  end

  #
  #
  @doc """
  Returns state of this node within the Beethoven cluster.
  Return will only be `:clustered` or `:standalone`.

  Wrapper for `Beethoven.CoreServer.get_mode/0`.
  """
  @spec get_node_status() :: CoreServer.serverStatus()
  def get_node_status() do
    CoreServer.get_mode()
  end

  #
  #
  @doc """
  Returns the Node URIs of all nodes that have joined the Beethoven Cluster
  """
  @spec get_cluster_nodes() :: nodeList()
  def get_cluster_nodes() do
    CoreServer.dirty_select([
      {
        {CoreServer.get_table_name(), :"$1", :_, :_},
        [],
        [:"$1"]
      }
    ])
  end

  #
  #
  @doc """
  Returns all active cluster nodes by their Node URI.
  """
  @spec get_active_cluster_nodes() :: nodeList()
  def get_active_cluster_nodes() do
    CoreServer.dirty_select([
      {
        {CoreServer.get_table_name(), :"$1", :"$2", :_},
        [{:==, :"$2", :online}],
        [:"$1"]
      }
    ])
  end

  #
  #
  @doc """
  Returns all cluster nodes and their state.

  # Example

      [%{node: node(), status: :online | :offline, last_change: DateTime.t()}]

  """
  @spec get_detailed_cluster_nodes() :: nodeStatusMapList()
  def get_detailed_cluster_nodes() do
    CoreServer.dirty_select([
      {
        {CoreServer.get_table_name(), :"$1", :"$2", :"$3"},
        [],
        [%{node: :"$1", status: :"$2", last_change: :"$3"}]
      }
    ])
  end

  #
  #
  @doc """
  Returns all Beethoven hosted roles with their associated metadata.
  """
  @spec get_roles() :: roleDefinitionList()
  def get_roles() do
    RoleServer.dirty_select([
      {
        {RoleServer.get_table_name(), :"$1", :"$2", :"$3", :"$4", :_},
        [],
        [%{role: :"$1", count: :"$2", assigned: :"$3", nodes: :"$4"}]
      }
    ])
  end

  #
  #
  @doc """
  Returns what nodes host a given role.
  """
  @spec whois_hosting(atom()) :: nodeList()
  def whois_hosting(role) do
    RoleServer.dirty_select([
      {
        {RoleServer.get_table_name(), :"$1", :_, :_, :"$2", :_},
        [{:==, :"$1", role}],
        [:"$2"]
      }
    ])
    |> List.flatten()
  end

  #
  #
  @doc """
  Returns the least-busy node from the Allocator's Mnesia table.

  Wrapper for `Beethoven.Allocator.allocate/0`.
  """
  @spec allocate() :: node()
  def allocate() do
    Allocator.allocate()
  end

  #
  #
end
