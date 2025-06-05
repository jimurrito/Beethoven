defmodule Beethoven.DistrServer do
  @moduledoc """
  A modified version of the built-in `GenServer`.
  Specialized for Beethoven's No-Master design; this GenServer will initialize a Mnesia table on creation.
  These tables act as the primary state for the distributed process.
  Supports *most* GenServer logic and callbacks.
  """

  require Logger
  import Beethoven.MnesiaTools
  alias Beethoven.DistrServer
  alias Beethoven.MnesiaTools
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
  """
  @type distrConfig() :: %{
          tableName: atom(),
          columns: list(atom()),
          indexes: list(atom()),
          dataType: atom(),
          copyType: copyTypes()
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
  @callback create_action(tableConfig :: MnesiaTools.tableConfig()) :: :ok
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
  defmacro __using__(subscribe?: subscribe) do
    #
    #
    quote do
      # force this modules behavior
      @behaviour Beethoven.DistrServer
      # Add CoreServer Callback for node down
      @behaviour Beethoven.CoreServer
      # Imports GenServer behaviors
      use GenServer
      # Imports mnesiaTools
      import Beethoven.MnesiaTools
      require Logger

      #
      #
      #
      def node_update(nodeName, status) do
        Logger.error(
          "The DistrServer invoked called back `node_update/2` is not declared for this module (#{__MODULE__}). Please add this call back before using `alert_me/1` again."
        )
      end

      defoverridable node_update: 2

      #
      #
      #
      def config() do
        %{
          tableName: __MODULE__.Tracker,
          columns: [:col0, :col1, :col2],
          indexes: [],
          dataType: :set,
          copyType: :local
        }
      end

      defoverridable config: 0

      #
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
          copyType: copyType
        } = config()

        # Create tableConfig type
        tableConfig = {tableName, columns, indexes, dataType, copyType}

        # Create table if it does not already exist
        :ok =
          create_table_ifnot_exist(tableConfig)
          |> case do
            # table was created
            :ok ->
              Logger.info(table: tableName, table_exists: true, created: true)
              create_action(tableConfig)

            # table already exists
            :already_exists ->
              Logger.info(table: tableName, table_exists: true, created: false)
              :ok
          end

        # Subscribes to table changes (if applicable)
        # Must copy to memory if you want to subscribe.
        unquote do
          if subscribe do
            #
            # When subscribing
            #
            quote do
              result = copy_table(tableName)
              {:ok, _node} = subscribe(tableName)

              Logger.info(
                table: tableName,
                subscribe?: true,
                copy_result: result,
                subscribe_result: :ok
              )
            end
          else
            #
            # When **NOT** subscribing
            #
            quote do
              Logger.info(
                table: tableName,
                subscribe?: false
              )
            end
          end
        end

        # execute user defined entry point
        entry_point(init_arg)
      end

      #
      #
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
  @spec call(GS.server(), any(), timeout()) :: any()
  def call(server, request, timeout \\ 5000) do
    GenServer.call(server, request, timeout)
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # LIB FUNCTIONS
  #
  #
  @doc """
  Converts the `DistrConfig()` into the `tableConfig()` type.
  """
  @spec distr_to_table_conf(DistrServer.distrConfig()) :: MnesiaTools.tableConfig()
  def distr_to_table_conf(distrConfig) do
    %{
      tableName: tableName,
      columns: columns,
      indexes: indexes,
      dataType: dataType,
      copyType: copyType
    } = distrConfig

    #
    {tableName, columns, indexes, dataType, copyType}
  end

  #
  #
end
