defmodule Beethoven.MnesiaTools do
  @moduledoc """
  Generic Library to simplify certain Mnesia tasks.
  """

  require Logger

  #
  #
  #
  @doc """
  Check if a Mnesia table exists in the cluster.
  """
  @spec table_exists?(atom()) :: boolean()
  def table_exists?(table) when is_atom(table) do
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
  Copies a replica of a desired table to local node memory.
  - Table must already exist in the cluster.
  - If the table was initialized on this node, the table is already in memory.
  - If node successfully joined in the past, but power-cycled, rebooting will automatically grab the tables from the cluster.

  """
  @spec copy_table(atom()) :: :ok | :already_exists | {:error, any()}
  def copy_table(table) do
    Logger.info("Making in-memory copies of the Mnesia Cluster table '#{table}'.")

    # Copy x table to self.
    :mnesia.add_table_copy(table, node(), :ram_copies)
    |> case do
      # Successfully copied table to memory
      {:atomic, :ok} ->
        Logger.info("Successfully copied table '#{table}' to memory.")
        :ok

      # table already in memory (this is fine)
      {:aborted, {:already_exists, _, _}} ->
        Logger.info("Table '#{table}' is already copied to memory.")
        :already_exists

      # Copy failed for some reason
      {:aborted, error} ->
        Logger.alert("Failed to copy table '#{table}' to memory.", error: error)
        {:error, error}
    end
  end

  #
  #
  #
  @doc """
  Removes the replica of a desired table from local memory.
  """
  @spec delete_copy(atom()) :: :ok
  def delete_copy(table) do
    Logger.info("Purging in-memory copies of the Mnesia Cluster table '#{table}'.")

    # remove table copy from self.
    :mnesia.del_table_copy(table, node())
    |> case do
      {:atomic, :ok} ->
        Logger.info("Successfully removed table '#{table}' from memory.")
        :ok

      # table already in memory (this is fine)
      {:aborted, _} ->
        Logger.info("Table '#{table}' was already deleted from memory.")
        :ok
    end
  end

  #
  #
  #
  @doc """
  Subscribe to changes to a Mnesia table.
  """
  @spec subscribe(atom()) :: {:ok, node()} | {:error, reason :: term()}
  def subscribe(tableName) do
    # :detailed is used to get the previous version of the record.
    :mnesia.subscribe({:table, tableName, :detailed})
  end

  #
  #
  @doc """
  Runs a job within a synchronous transaction
  """
  @spec sync_run((-> any())) :: any() | {:error, any()}
  def sync_run(fun) do
    :mnesia.sync_transaction(fun)
  end

  #
  #
end
