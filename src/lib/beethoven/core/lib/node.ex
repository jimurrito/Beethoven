defmodule Beethoven.Core.Lib.Node do
  @moduledoc """
  Library to reduce code length of Core server.
  Only handles `hand_info` messages about Monitored node health.
  """

  require Logger
  alias Beethoven.Utils
  alias Beethoven.Core, as: CoreServer
  alias Beethoven.Role, as: RoleServer

  #
  #
  #
  @doc """
  Handles what happens when a node goes down.
  """
  @spec down(atom()) :: :ok
  def down(nodeName) do
    Logger.warning("Node (#{nodeName}) has gone offline.")
    # backoff in milliseconds (random number between 5-8.5 seconds)
    Utils.backoff(10, 9, 500)

    # attempt ping
    Node.ping(nodeName)
    |> case do
      #
      #
      # Server is backup -> re-enable monitoring
      :pong ->
        Logger.info("Node (#{nodeName}) is back online.")
        GenServer.cast(CoreServer, {:mon_node, {:start, nodeName}})

      #
      #
      # Server is still unreachable -> attempt status change.
      :pang ->
        # update node state from :online to :offline
        {:atomic, :ok} =
          :mnesia.transaction(fn ->
            # See if the node still shows online
            :mnesia.read(BeethovenTracker, nodeName)
            |> case do
              # Node still marked as online on the table -> update
              [{BeethovenTracker, ^nodeName, _role, :online, _}] ->
                Logger.debug(
                  "Node (#{nodeName}) unreachable via ping, but the status still shows ':online' in Mnesia. Updating Mnesia."
                )

                # Write updated state to table
                :ok =
                  :mnesia.write(
                    {BeethovenTracker, nodeName, :down, :offline, DateTime.now!("Etc/UTC")}
                  )

                # Check if there are any other nodes
                if length(Node.list()) == 0 do
                  # Standalone is now needed. All others are offline.
                  GenServer.cast(CoreServer, :clustered_to_standalone)
                else
                  # Other nodes exist in cluster.
                  # Run :check on RoleServer
                  GenServer.cast(RoleServer, :check)
                end

              # Node was deleted -> do nothing
              [] ->
                Logger.debug("Node (#{nodeName}) was already deleted from Mnesia.")
                :ok

              # Node was already updated to offline. -> do nothing
              _ ->
                Logger.debug("Node (#{nodeName}) is already updated in Mnesia.")
                :ok
            end
          end)
    end
  end
end
