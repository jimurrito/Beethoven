defmodule Beethoven.Core.Lib.MnesiaNotify do
  @moduledoc """
  Library to reduce code length of Core server.
  Only handles `hand_info` messages about Mnesia changes.

  All functions have no side_effects
  """

  require Logger
  alias Beethoven.Core, as: CoreServer

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
       [{BeethovenTracker, nodeName, :member, :offline, _}], _pid_struct} ->
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
    # Sending cast ensure we are monitoring the new node
    GenServer.cast(CoreServer, {:mon_node, {:start, nodeName}})
  end

  #
  #
  @doc """
  Node changed from online to offline in 'BeethovenTracker' table
  """
  @spec offline_node(atom()) :: :ok
  def offline_node(nodeName) do
    Logger.debug("Node (#{nodeName}) has changed availability: [:online] => [:offline].")
    # Sending cast ensure we stop monitoring the offline node
    GenServer.cast(CoreServer, {:mon_node, {:stop, nodeName}})
  end

  #
  #
  @doc """
  Node changed from offline to online in 'BeethovenTracker' table
  """
  @spec online_node(atom()) :: :ok
  def online_node(nodeName) do
    Logger.debug("Node (#{nodeName}) has changed availability: [:offline] => [:online].")
    # Sending cast ensure we start monitoring the offline node again
    GenServer.cast(CoreServer, {:mon_node, {:start, nodeName}})
  end

  #
  #
end
