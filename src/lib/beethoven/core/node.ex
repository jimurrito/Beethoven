defmodule Beethoven.Core.Node do
  @moduledoc """
  Library to reduce code length of Core server.
  Only handles `hand_info` messages about Monitored node health.
  """

  require Logger
  alias Beethoven.Core.Client, as: CoreClient
  alias Beethoven.RoleAlloc
  alias Beethoven.Utils

  #
  #
  #
  @doc """
  Handles what happens when a node goes down.
  """
  @spec down(atom()) :: :ok
  def down(nodeName) do
    Logger.warning("Node (#{nodeName}) has gone offline.")
    # backoff in milliseconds (random number between 0.50-5.0 seconds)
    Utils.backoff_n(Core.NodeDown, 10, 0, 500)

    # attempt ping
    Node.ping(nodeName)
    |> case do
      #
      #
      # Server is backup -> re-enable monitoring
      :pong ->
        Logger.info("Node (#{nodeName}) is back online.")
        Utils.monitor_node(nodeName, true)

      #
      #
      # Server is still unreachable -> attempt status change.
      :pang ->
        # update node state from :online to :offline
        #
        {:atomic, :ok} =
          fn ->
            # See if the node still shows online
            :mnesia.wread({Beethoven.Tracker, nodeName})
            |> case do
              # Node still marked as online on the table -> update
              [{Beethoven.Tracker, ^nodeName, roles, :online, _}] ->
                Logger.debug(
                  "Node (#{nodeName}) still unreachable via ping. Updating Beethoven.Tracker."
                )

                # Write updated state to table
                :ok =
                  :mnesia.write(
                    {Beethoven.Tracker, nodeName, roles, :offline, DateTime.now!("Etc/UTC")}
                  )

                # Check if there are any other nodes
                if length(Node.list()) == 0 do
                  # Call Core Genserver and transition to standalone as we are now alone
                  _ = CoreClient.to_standalone()
                else
                  # Other nodes exist in cluster.
                  # attempt to start role alloc server incase its not running
                  _ = RoleAlloc.async_start()
                end

                # return atom
                :ok

              # Node was deleted -> do nothing
              [] ->
                Logger.debug("Node (#{nodeName}) was deleted from Beethoven.Tracker.")
                :ok

              # Node was already updated to offline. -> do nothing
              _ ->
                Logger.debug("Node (#{nodeName}) is already updated in Beethoven.Tracker.")
                :ok
            end
          end
          #
          |> :mnesia.transaction(:infinity)
    end
  end
end
