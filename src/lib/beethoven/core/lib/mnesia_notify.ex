defmodule Beethoven.Core.Lib.MnesiaNotify do
  @moduledoc """
  Library to reduce code length of Core server.
  Only handles `hand_info` messages about Mnesia changes.

  All functions have no side_effects
  """

  require Logger
  alias Beethoven.Utils
  alias Beethoven.Role, as: RoleServer

  @doc """
  Entry function to decide what is done when the Mnesia Event occurs.
  """
  @spec run(any()) :: :ok
  def run(event) do
    event
    |> case do
      #
      # New node was added to the 'BeethovenTracker' table
      {:write, BeethovenTracker, {BeethovenTracker, nodeName, _, :online, _}, [], _pid_struct} ->
        new_node(nodeName)

      # Node changed from online to offline in 'BeethovenTracker' table
      {:write, BeethovenTracker, {BeethovenTracker, nodeName, _, :offline, _},
       [{BeethovenTracker, nodeName, _, :online, _}], _pid_struct} ->
        offline_node(nodeName)

      # Node changed from offline to online in 'BeethovenTracker' table
      {:write, BeethovenTracker, {BeethovenTracker, nodeName, :member, :online, _},
       [{BeethovenTracker, nodeName, _, :offline, _}], _pid_struct} ->
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
  Logic when a new node is added to the 'BeethovenTracker' table / Cluster
  """
  @spec new_node(atom()) :: :ok
  def new_node(nodeName) do
    Logger.debug("Node (#{nodeName}) as been added to 'BeethovenTracker' table.")
    # Monitor new node
    Utils.monitor_node(nodeName, true)
  end

  #
  #
  @doc """
  Node changed from online to offline in 'BeethovenTracker' table
  """
  @spec offline_node(atom()) :: :ok
  def offline_node(nodeName) do
    Logger.debug("Node (#{nodeName}) has changed availability: [:online] => [:offline].")
    # Run :check on RoleServer
    GenServer.cast(RoleServer, :check)
    # Ensure we stop monitoring the node
    Utils.monitor_node(nodeName, false)
  end

  #
  #
  @doc """
  Node changed from offline to online in 'BeethovenTracker' table
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
