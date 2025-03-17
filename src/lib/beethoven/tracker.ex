defmodule Beethoven.Tracker do
  @moduledoc """
  State tracking for the Beethoven services. Uses Mnesia.
  Tabled named 'BeethovenTracker'
  """

  require Logger

  @doc """
  Starts tracker Mnesia table
  """
  @spec start() :: :ok | :already_exists
  def start() do
    # checks if table already exists
    if exists?() do
      :already_exists
    else
      Logger.debug("Creating 'BeethovenTracker' mnesia table.")

      :mnesia.create_table(BeethovenTracker,
        attributes: [:node, :role, :health, :last_change],
        # Sets ram copies for ALL existing nodes in the cluster
        ram_copies: [node() | Node.list()],
        # This is so it works like a queue
        type: :ordered_set
      )

      # Create indexes - speeds up searches for data that does not regularly change
      Logger.debug("Creating Indexes in 'BeethovenTracker'")
      :mnesia.add_table_index(BeethovenTracker, :node)
      # Add self to tracker
      :ok = add_self()
      # Subscribe to tracker
      {:ok, _node} = subscribe()
      #
      :ok
    end
  end

  @doc """
  Add self to tracker
  """
  @spec join() :: :ok | :not_started | :copy_error
  def join() do
    if not exists?() do
      :not_started
    else
      # Add self to tracker
      :ok = add_self()
      # Copy table to local memory
      copy_table(BeethovenTracker)
      |> case do
        # Copied table to memory
        :ok ->
          # Subscribe to tracker
          {:ok, _node} = subscribe()
          #
          :ok

        # Failed to copy to memory
        {:error, _error} ->
          :copy_error
      end
    end
  end

  @doc """
  Check if tracking table exists.
  """
  def exists? do
    Logger.debug("Checking if 'BeethovenTracker' mnesia table exists.")

    :mnesia.system_info(:tables)
    |> Enum.member?(BeethovenTracker)
    |> if do
      Logger.debug("'BeethovenTracker' table exists.")
      true
    else
      Logger.debug("'BeethovenTracker' table does not exist.")
      false
    end
  end

  @doc """
  Copies desired table to local node memory
  """
  @spec copy_table(atom()) :: :ok | {:error, any()}
  def copy_table(table) do
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
        Logger.error(
          "Failed to copy table '#{Atom.to_string(table)}' to memory. Going into failed state."
        )

        {:error, error}
    end
  end

  @doc """
  Adds self to BeethovenTracking Mnesia table.
  """
  @spec add_self() :: :ok
  def add_self(role \\ :member) do
    # Add self to tracker
    Logger.debug("Adding self to 'BeethovenTracker' Mnesia table.")

    {:atomic, :ok} =
      :mnesia.transaction(fn ->
        :mnesia.write({BeethovenTracker, node(), role, :online, DateTime.now!("Etc/UTC")})
      end)

    :ok
  end

  @doc """
  Subscribe to changes to the BeethovenTracking Mnesia table
  """
  @spec subscribe() :: {:ok, node()} | {:error, reason :: term()}
  def subscribe() do
    # Subscribe to tracking table
    :mnesia.subscribe({:table, BeethovenTracker, :detailed})
  end
end
