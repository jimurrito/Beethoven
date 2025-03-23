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

  #
  #
  @doc """
  Check if Mnesia table exists
  """
  @spec mnesia_table_exists?(atom()) :: boolean()
  def mnesia_table_exists?(table) when is_atom(table) do
    Logger.debug("Checking if '#{table}' mnesia table exists.")

    :mnesia.system_info(:tables)
    |> Enum.member?(table)
    |> if do
      Logger.debug("'#{table}' table exists.")
      true
    else
      Logger.debug("'#{table}' table does not exist.")
      false
    end
  end

  #
  #
  #
  @doc """
  Copies desired table to local node memory
  """
  @spec copy_mnesia_table(atom()) :: :ok | {:error, any()}
  def copy_mnesia_table(table) do
    Logger.info("Making in-memory copies of the Mnesia Cluster table '#{Atom.to_string(table)}'.")

    :mnesia.add_table_copy(table, node(), :ram_copies)
    |> case do
      # Successfully copied table to memory
      {:atomic, :ok} ->
        Logger.info("Successfully copied table '#{Atom.to_string(table)}' to memory.")
        :ok

      # table already in memory (this is fine)
      {:aborted, {:already_exists, _, _}} ->
        Logger.info("Table '#{Atom.to_string(table)}' is already copied to memory.")
        :ok

      # Copy failed for some reason
      {:aborted, error} ->
        Logger.error("Failed to copy table '#{Atom.to_string(table)}' to memory.")

        {:error, error}
    end
  end

  #
  #
  @doc """
  Runs a job within a synchronous transaction
  """
  @spec sync_run((-> :ok)) :: {:atomics, :ok} | {:error, any()}
  def sync_run(fun) do
    :mnesia.sync_transaction(fun)
  end
end
