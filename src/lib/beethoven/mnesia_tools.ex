defmodule Beethoven.MnesiaTools do
  @moduledoc """
  Generic Library to simplify certain Mnesia tasks.
  """

  require Logger

  #
  #
  @typedoc """
  TableConfig contains the payload needed to create the state table needed by the process.
  """
  @type tableConfig() :: {atom(), list(atom()), list(atom()), atom(), atom()}

  #
  #
  #
  @doc """
  Check if a Mnesia table exists in the cluster.
  """
  @spec table_exists?(atom()) :: boolean()
  def table_exists?(table) when is_atom(table) do
    result = :mnesia.system_info(:tables) |> Enum.member?(table)
    Logger.debug(tableName: table, table_exists?: result)
    result
  end

  #
  #
  #
  @doc """

  """
  @spec apply_indexes(tableConfig()) :: :ok
  def apply_indexes({tableName, _columns, indexes, _type, _copy}) do
    indexes
    |> Enum.each(&:mnesia.add_table_index(tableName, &1))
  end

  #
  #
  #
  @doc """
  Creates table if it does not already exist.
  Applies indexes on creation.
  """
  @spec create_table_ifnot_exist(tableConfig()) :: :ok | :already_exists
  def create_table_ifnot_exist(tableConfig) do
    #
    {tableName, columns, _indexes, type, copy} = tableConfig
    #
    copy_type =
      case copy do
        :local -> [node()]
        :multi -> [node() | Node.list()]
      end

    # If the input table does not exist
    result =
      if not table_exists?(tableName) do
        # Create table
        {:atomic, :ok} =
          :mnesia.create_table(tableName,
            # Table schema
            attributes: columns,
            # Sets ram copies for ALL existing nodes in the cluster.
            ram_copies: copy_type,
            # This setting orders the table by order the nodes joined the cluster.
            type: type
          )

        # Applies indexes
        apply_indexes(tableConfig)
      else
        # Already created
        :already_exists
      end

    Logger.debug(
      status: result,
      tableName: tableName,
      type: type,
      copyType: copy
    )

    #
    result
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
    Logger.info("Making in-memory copy of the Mnesia table '#{table}'.")

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
        Logger.alert("Failed to copy table '#{table}' to memory.")
        Logger.alert(error: error)
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
    Logger.debug("Subscribed to '#{tableName}'.")
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
