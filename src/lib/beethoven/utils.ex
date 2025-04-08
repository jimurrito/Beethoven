defmodule Beethoven.Utils do
  @moduledoc """
  Module for generic utilities.
  """

  require Logger

  #
  #
  #
  @doc """
  Fn to simplify calling named Processes on other nodes... and getting a call back.
  """
  @spec remote_call((-> any()), node(), integer()) :: any() | {:error, :timeout}
  def remote_call(fun, host, timeout \\ 1_000) do
    # generate seed for tracking (100_000-999_9999)
    seed = :rand.uniform(900_000) + 99_999
    # ownPID
    ownPid = self()
    #
    # Fun that will be ran in the remote host
    remote_fun = fn ->
      # run input fn
      result = fun.()
      # Send back to original caller
      _ = send(ownPid, {:remote_call, seed, result})
    end

    # Spawn PID on remote node
    _ = Node.spawn(host, remote_fun)

    # Await response
    receive do
      {:remote_call, ^seed, response} ->
        response
    after
      # Timeout awaiting response
      timeout ->
        {:error, :timeout}
    end
  end

  #
  #
  #
  @doc """
  Gets an environmental variable from beethoven's application config
  """
  def get_app_env(envVar, default \\ nil) do
    Application.fetch_env(:beethoven, envVar)
    |> case do
      # Got roles from application env
      {:ok, value} ->
        value

      # No roles found, return empty list.
      :error ->
        Logger.warning("{:#{envVar}} is not set in config/*.exs. Using:",
          default_value: default
        )

        default
    end
  end

  #
  #
  #
  @doc """
  The same as `backoff/3` but shows the calling service's name in the verbose output.

  Performs a backoff wait to void race conditions in a distributed environment.
  (:rand.uniform(1..max) + delta) * multiplier
  """
  @spec backoff_n(atom(), integer(), integer(), integer()) :: :ok
  def backoff_n(name, max \\ 20, delta \\ 0, multiplier \\ 1) when is_atom(name) do
    # backoff in milliseconds
    backoff = (:rand.uniform(max) + delta) * multiplier
    Logger.info("[#{name}] Backoff for (#{backoff |> Integer.to_string()}) milliseconds started.")
    Process.sleep(backoff)
  end

  #
  #
  #
  @doc """
  Performs a backoff wait to void race conditions in a distributed environment.
  (:rand.uniform(1..max) + delta) * multiplier
  """
  @spec backoff(integer(), integer(), integer()) :: :ok
  def backoff(max \\ 20, delta \\ 0, multiplier \\ 1) do
    # backoff in milliseconds
    backoff = (:rand.uniform(max) + delta) * multiplier
    Logger.info("Backoff for (#{backoff |> Integer.to_string()}) milliseconds started.")
    Process.sleep(backoff)
  end

  #
  #
  #
  @doc """
  Toggles the monitoring status of another node in the cluster.
  """
  @spec monitor_node(node(), boolean()) :: :ok
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
  @doc """
  Retrieves roles from config and converts to map.
  """
  @spec get_role_config() :: map()
  def get_role_config() do
    # get roles from config.exs
    get_app_env(:roles, [])
    # converts to map
    |> role_list_to_map()
  end

  #
  #
  #
  @doc """
  Creates a map from a list of maps. First element of the map needs to be an atom.
  This same atom will be the key for the rest of the data in the map.
  """
  def role_list_to_map(role_list) do
    role_list_to_map(role_list, %{})
  end

  # End loop
  defp role_list_to_map([], state) do
    state
  end

  # Working loop
  defp role_list_to_map([{role_name, mod, args, inst} | role_list], state)
       when is_atom(role_name) do
    state = state |> Map.put(role_name, {mod, args, inst})
    role_list_to_map(role_list, state)
  end

  # Working loop - bad syntax for role manifest
  defp role_list_to_map([role_bad | role_list], state) do
    Logger.error(
      "One of the roles provided is not in the proper syntax. This role will be ignored.",
      expected: "{:role_name, Module, ['args'], 1}",
      received: role_bad
    )

    role_list_to_map(role_list, state)
  end

  #
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
  Copies desired table to local node memory.
  - Table must already exist in the cluster.
  - If the table was initialized on this node, the table is already in memory.
  - If node successfully joined in the past, but power-cycled, rebooting will automatically grab the tables from the cluster.

  """
  @spec copy_mnesia_table(atom()) :: :ok | :already_exists | {:error, any()}
  def copy_mnesia_table(table) do
    Logger.info("Making in-memory copies of the Mnesia Cluster table '#{Atom.to_string(table)}'.")

    # Copy x table to self.
    :mnesia.add_table_copy(table, node(), :ram_copies)
    |> case do
      # Successfully copied table to memory
      {:atomic, :ok} ->
        Logger.info("Successfully copied table '#{Atom.to_string(table)}' to memory.")
        :ok

      # table already in memory (this is fine)
      {:aborted, {:already_exists, _, _}} ->
        Logger.info("Table '#{Atom.to_string(table)}' is already copied to memory.")
        :already_exists

      # Copy failed for some reason
      {:aborted, error} ->
        Logger.alert("Failed to copy table '#{Atom.to_string(table)}' to memory.", error: error)
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
