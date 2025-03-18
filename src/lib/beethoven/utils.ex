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
