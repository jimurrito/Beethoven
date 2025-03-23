defmodule Beethoven.Utils do
  @moduledoc """
  Module for generic utilities.
  """

  require Logger

  @doc """
  Performs a backoff wait to void race conditions in a distributed environment.
  (:rand.uniform(1 - max) + delta) * multiplier
  """
  def backoff(max \\ 20, delta \\ 0, multiplier \\ 1) do
    # backoff in milliseconds
    backoff = (:rand.uniform(max) + delta) * multiplier
    Logger.debug("Backoff for (#{backoff |> Integer.to_string()}) milliseconds started.")
    Process.sleep(backoff)
  end

  #
  #
  #
  @doc """
  Toggles the monitoring status of another node in the cluster.
  """
  @spec monitor_node(atom(), boolean()) :: :ok
  def monitor_node(nodeName, mode) do
    Logger.info("Monitoring on node (#{nodeName}) has been set to (#{mode}).")
    true = Node.monitor(nodeName, mode)
    :ok
  end

  #
  #
  #
  @doc """
  Toggles the monitoring status of **all** nodes in the cluster.
  """
  @spec monitor_all_nodes(boolean()) :: :ok
  def monitor_all_nodes(mode) do
    list = Node.list()
    Logger.info("Monitoring all (#{length(list) |> to_string}) node(s) in the cluster.")

    Node.list()
    |> Enum.each(fn node ->
      true = Node.monitor(node, mode)
    end)
  end

  #
  #
  #
  #
  @doc """
  Merges an existing map, and a list of maps into a single level map.
  """
  def bulk_put(map, list_o_maps) when is_map(map) do
    bulk_put(map, list_o_maps, map)
  end

  # Exit
  defp bulk_put(_map, [], state) do
    state
  end

  # worker
  defp bulk_put(map, [head | list_o_maps], state) when is_list(list_o_maps) do
    [key] = head |> Map.keys()
    value = head |> Map.get(key)
    state = state |> Map.put(key, value)
    bulk_put(map, list_o_maps, state)
  end
end
