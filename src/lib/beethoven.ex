defmodule Beethoven do
  @moduledoc """
  A Decentralized failover and peer-to-peer node finder for Elixir.
  Allows Elixir nodes to find each other automatically.
  Once connected, they can coordinate to delegate roles and tasks between the nodes in the cluster.
  Written using only the Elixir and Erlang standard library.

  This module acts as the unified client for interacting with beethoven as an external client.
  Avoid using the other modules for external PID calls to beethoven services.
  """

  alias Beethoven.CoreServer
  alias Beethoven.RoleServer

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
  @type role() :: %{role: atom(), count: integer(), assigned: integer(), nodes: nodeList()}

  #
  @typedoc """
  List of `role()`.
  """
  @type roleList() :: list(role())


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
  Returns all active cluster nodes by their Node name URI.
  Returns an empty list if this node is in `:standalone`.
  """
  @spec get_active_nodes() :: nodeList()
  def get_active_nodes() do
    [node() | Node.list()]
  end

  #
  #
  @doc """
  Returns all cluster nodes and their state.
  """
  @spec get_cluster_nodes() :: nodeStatusMapList()
  def get_cluster_nodes() do
    tableName = CoreServer.Tracker
    #

    :mnesia.dirty_select(tableName, [
      {
        {tableName, :"$1", :"$2", :"$3"},
        [],
        [%{node: :"$1", status: :"$2", last_change: :"$3"}]
      }
    ])
  end

  #
  #
  @doc """
  Returns all roles hosted in Beethoven.
  """
  @spec get_roles() :: roleList()
  def get_roles() do
    tableName = RoleServer.Tracker
    #
    :mnesia.dirty_select(tableName, [
      {
        {tableName, :"$1", :"$2", :"$3", :"$4", :_},
        [],
        [%{role: :"$1", count: :"$2", assigned: :"$3", nodes: :"$4"}]
      }
    ])
  end

  #
  #
end
