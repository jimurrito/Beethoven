defmodule Beethoven.Core.Lib.Node do
  @moduledoc """
  Library to reduce code length of Core server.
  Only handles `hand_info` messages about Monitored node health.
  """

  require Logger
  alias Beethoven.Core, as: CoreServer
  alias Beethoven.RoleAlloc
  alias Beethoven.Utils
  alias Beethoven.Core.TaskSupervisor, as: CoreSupervisor

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
                  # can call CoreServer since this fun will be used by a task
                  _ = GenServer.call(CoreServer, {:transition, :standalone})
                else
                  # Other nodes exist in cluster.
                  # attempt to start role alloc server incase its not running
                  _ =
                    Task.Supervisor.start_child(
                      CoreSupervisor,
                      fn ->
                        Supervisor.start_child(RootSupervisor, RoleAlloc)
                      end
                    )

                  :ok
                end

                :ok

              # Node was deleted -> do nothing
              [] ->
                Logger.debug("Node (#{nodeName}) was already deleted from Beethoven.Tracker.")
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
