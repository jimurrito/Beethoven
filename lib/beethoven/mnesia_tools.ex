defmodule Beethoven.MnesiaTools do
  @moduledoc """
  Generic Library to simplify certain Mnesia tasks.
  """

  #
  #
  @typedoc """
  TableConfig contains the payload needed to create the state table needed by the process.
  """
  @type tableConfig() ::
          {tableName :: atom(), columns :: list(atom()), indexes :: list(atom()),
           dataType :: atom(), copyType :: atom()}

  #
  #
  #
  @doc """
  Check if a Mnesia table exists in the cluster.
  """
  @spec table_exists?(atom()) :: boolean()
  def table_exists?(table) when is_atom(table) do
    :mnesia.system_info(:tables) |> Enum.member?(table)
  end

  #
  #
  #
  @doc """
  Creates table if it does not already exist.
  Applies indexes on creation.
  Will
  """
  @spec create_table_ifnot_exist(tableConfig()) :: :ok | :already_exists
  def create_table_ifnot_exist(tableConfig) do
    #
    {tableName, columns, indexes, type, copy_type} = tableConfig
    #
    ram_copies =
      case copy_type do
        :local -> [node()]
        :multi -> [node() | Node.list()]
      end

    # If the input table does not exist
    if not table_exists?(tableName) do
      # Create table
      {:atomic, :ok} =
        :mnesia.create_table(tableName,
          # Table schema
          attributes: columns,
          # Sets ram copies for ALL existing nodes in the cluster.
          ram_copies: ram_copies,
          # This setting orders the table by order the nodes joined the cluster.
          type: type,
          # indexes
          index: indexes
        )

      :ok

      #
    else
      # if multi, attempt to copy table to memory
      if copy_type == :multi do
        _result = copy_table(tableName)
      end

      # Already created
      :already_exists
    end
  end

  #
  #
  #
  @doc """
  Copies a replica of a desired table to local node memory.

  The table may already exist in memory for the following reasons:
  - The table was created for all nodes, and this node was already in the cluster.
  - The table was initialized on this node.
  - A node with the same name was successfully joined the cluster in the past, and power-cycled.
  """
  @spec copy_table(atom()) :: :ok | :already_exists | {:error, any()}
  def copy_table(table) do
    # Copy x table to self.
    :mnesia.add_table_copy(table, node(), :ram_copies)
    |> case do
      # Successfully copied table to memory
      {:atomic, :ok} ->
        :ok

      # table already in memory (this is fine)
      {:aborted, {:already_exists, _, _}} ->
        :already_exists

      # Copy failed for some reason
      {:aborted, error} ->
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
    # remove table copy from self.
    :mnesia.del_table_copy(table, node())
    |> case do
      {:atomic, :ok} ->
        :ok

      # table already in memory (this is fine)
      {:aborted, _} ->
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
