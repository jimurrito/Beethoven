defmodule Beethoven.DistrServer do
  @moduledoc """
  A modified version of the built-in `GenServer`.
  Specialized for Beethoven's No-Master design; this GenServer will initialize a Mnesia table on creation.
  These tables act as the primary state for the distributed process.
  Supports *most* GenServer logic and callbacks.
  """

  require Logger
  import Beethoven.MnesiaTools
  alias GenServer, as: GS

  #
  # UNIQUE TYPES
  #
  #
  @typedoc """
  Copy options for the Mnesia table.
  - `:local` -> Copies are only on the table-creating-node.
  - `:multi` -> Copies are pushed to ALL nodes in the cluster.
  """
  @type copyTypes() :: :local | :multi
  #
  #
  @typedoc """
  Configuration for the `DistrServer` instance.
  - `:tableName` -> Atomic name for the table.
  - `:columns` -> List of atoms representing the names of columns in the name.
  - `:indexes` -> List of table columns that should be indexed.
  **Note:** Indexing a column will slow writes to it,
  but make read operations consistent regardless of the table's size.
  - `:dataType` -> Data type for the Mnesia table.
  - `:copyType` -> How the new table will be copied across the Beethoven cluster.
  - `:subscribe?` -> Whether to subscribe to Mnesia table changes or not.
  """
  @type distrConfig() :: %{
          tableName: atom(),
          columns: list(atom()),
          indexes: list(atom()),
          dataType: atom(),
          copyType: copyTypes(),
          subscribe?: boolean()
        }

  #
  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # UNIQUE CALL BACKS
  #
  #
  @doc """
  **-Callback required-**\n
  `DistrServer` configuration. See `distrConfig()` type for more information on the return.
  """
  @callback config() :: distrConfig()
  #
  @doc """
  **-Callback required-**\n
  Entry point for the `DistrServer` process. Similar to `init/1` for GenServers.
  """
  @callback entry_point(var :: any()) :: {:ok, var :: any()}
  #
  @doc """
  **-Callback required-**\n
  Callback that is triggered when the process creates the Mnesia Table for the cluster.
  """
  @callback create_action() :: :ok
  #
  #
  # MASKED CALL BACKS

  #
  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # `USE` MACRO
  #
  #
  @doc false
  defmacro __using__(_opts) do
    #
    quote do
      # force this modules behavior
      # Commented out until callbacks
      @behaviour Beethoven.DistrServer
      # Imports GenServer behaviors
      use GenServer
      # Imports mnesiaTools
      import Beethoven.MnesiaTools
      #
      #
      @impl true
      def init(init_arg) do
        # get config from callback
        %{
          tableName: tableName,
          columns: columns,
          indexes: indexes,
          dataType: dataType,
          copyType: copyType,
          subscribe?: subscribe?
        } = config()

        # Create table if it does not already exist
        :ok =
          create_table_ifnot_exist({tableName, columns, indexes, dataType, copyType})
          |> case do
            # table was created
            :ok -> create_action()
            # table already exists
            :already_exists -> :ok
          end

        # Subscribes to table changes (if applicable)
        if subscribe? do
          {:ok, _node} = subscribe(tableName)
        end

        # execute user defined entry point
        entry_point(init_arg)
      end
    end
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # MASKED FUNCTIONS
  #
  @doc """
  Starts a `DistrServer` process under the supervisor tree.
  Similar to `GenServer.start_link/2` and `GenServer.start_link/3`
  """
  @spec start_link(module(), any(), GS.options()) :: GS.on_start()
  def start_link(module, init_args, options \\ []) do
    GS.start_link(module, init_args, options)
  end

  #
  #
  @doc """
  Sends a cast to the provided `DistrServer`. Similar to `GenServer.cast/2`
  """
  @spec cast(GS.server(), any()) :: :ok
  def cast(server, request) do
    GenServer.cast(server, request)
  end

  #
  #
  @doc """
  Sends a cast to the provided `DistrServer`.
  Similar to `GenServer.call/2` and `GenServer.call/3`
  """
  @spec call(GS.server(), any(), timeout()) :: :ok
  def call(server, request, timeout \\ 5000) do
    GenServer.call(server, request, timeout)
  end

  #
  #
end
