defmodule Beethoven.Core.MnesiaNotify do
  @moduledoc """
  Library to reduce code length of Core server.
  Only handles `hand_info` messages about Mnesia changes.
  """

  require Logger
  alias Beethoven.Core.Listener
  alias Beethoven.Utils
  alias Beethoven.RoleAlloc

  @doc """
  Entry function to decide what is done when the Mnesia Event occurs.
  """
  @spec run(any()) :: :ok
  def run(event) do
    event
    |> case do
      #
      # New node was added to the 'Beethoven.Tracker' table
      {:write, Beethoven.Tracker, {Beethoven.Tracker, nodeName, _, :online, _}, [], _pid_struct}
      when nodeName != node() ->
        new_node(nodeName)

      # Node changed from online to offline in 'Beethoven.Tracker' table
      {:write, Beethoven.Tracker, {Beethoven.Tracker, nodeName, _, :offline, _},
       [{Beethoven.Tracker, nodeName, _, :online, _}], _pid_struct}
      when nodeName != node() ->
        offline_node(nodeName)

      # Node changed from offline to online in 'Beethoven.Tracker' table
      {:write, Beethoven.Tracker, {Beethoven.Tracker, nodeName, _, :online, _},
       [{Beethoven.Tracker, nodeName, _, :offline, _}], _pid_struct}
      when nodeName != node() ->
        online_node(nodeName)

      # Catch all
      _ ->
        :ok
        #
        #
    end
  end

  #
  #
  @doc """
  Logic when a new node is added to the 'Beethoven.Tracker' table / Cluster
  """
  @spec new_node(atom()) :: :ok
  def new_node(nodeName) do
    Logger.debug("Node (#{nodeName}) as been added to 'Beethoven.Tracker' table.")
    # Monitor new node
    Utils.monitor_node(nodeName, true)
  end

  #
  #
  @doc """
  Node changed from online to offline in 'Beethoven.Tracker' table
  """
  @spec offline_node(atom()) :: :ok
  def offline_node(nodeName) do
    Logger.debug("Node (#{nodeName}) has changed availability: [:online] => [:offline].")

    # Ensure we stop monitoring the node
    Utils.monitor_node(nodeName, false)

    # attempt to start role alloc server and listener incase its not running
    _ = Listener.async_start()
    # async_timed_start/0 uses a backoff to avoid race conditions
    _ = RoleAlloc.async_timed_start()
  end

  #
  #
  @doc """
  Node changed from offline to online in 'Beethoven.Tracker' table
  """
  @spec online_node(atom()) :: :ok
  def online_node(nodeName) do
    Logger.debug("Node (#{nodeName}) has changed availability: [:offline] => [:online].")
    # Monitor node again
    Utils.monitor_node(nodeName, true)
  end

  #
  #
end
