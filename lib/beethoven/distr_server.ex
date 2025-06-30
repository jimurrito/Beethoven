defmodule Beethoven.DistrServer do
  @moduledoc """
  Distr(ibuted)Server is a modified `GenServer` that allows for seamless integration with a dedicated Mnesia table.
  This was specially built for operation in a Beethoven environment.
  The idea is that the brain of the genserver can be set with mnesia and not the GenServer's internal state.
  This allows for the compute and state of the genserver to be distributed across the Beethoven cluster.

  Supports all GenServer logic and callbacks except for `init/1`.
  Use of this callback directly will cause unexpected errors and behaviour.
  The entry point for the DistrServer is `entry_point/1`.
  `entry_point/1` is identical to `init/1` in terms of both input and return types.

  # Example

      defmodule Test do

        use DistrServer, subscribe?: true

        # Standard OTP entry point for starting the PID.
        def start_link(init_args) do
          DistrServer.start_link(__MODULE__, init_args, name: __MODULE__)
        end

        # The configuration for the DistrServer's Mnesia table.
        @impl true
        def config() do
          %{
            tableName: TestTracker,
            columns: [:col1, :col2, :last_change],
            indexes: [],
            dataType: :set,
            copyType: :multi
          }
        end

        # This is ran when the table is newly created.
        @impl true
        def create_action(_tableConfig) do
          ...
          :ok
        end

        # Similar to GenServer.init/1.
        @impl true
        def entry_point(_init_args) do
          ...
          {:ok, :ok} # all init/1 returns are supported.
        end

      end

  ---

  # Breakdown

  - `use DistrServer, subscribe?: boolean()` -> This implements the DistrServer behaviour and mnesia tool functions.
      - `:subscribe?` Utilizing this required parameter will tell the compiler if the DistrServer should automatically subscribe to the Mnesia table it is entangled with.
          Subscribing to the table **will** copy it to the local memory of the node running this DistrServer.


  - `DistrServer.start_link/1` -> Similar to `GenServer.start_link/1`. Supports all the same arguments and arty.

  - **Callback:** `config/0` -> Provides the configuration that will be used by the DistrServer's Mnesia table.
      See the section below on `config/0` for more information

  - **Callback:** `create_action/1` -> Logic ran if the DistrServer has to create the Mnesia table.
      This callback is optional, but with it, you can pre-fill the mnesia table with data as needed.
      If the DistrServer boots and the table already exists in the cluster, this function will not be called.

  - **Callback:** `entry_point/1` -> Similar to `GenServer.init/1`. Supports all the same arguments and arty.
      With DistrServer, the `init/1` callback for GenServers is used in the creation of the Mnesia table.

  ---

  # `config/0`

  `config/0` is a callback that requires the returns of a specific map.

  # Example

        def config() do
        %{
          tableName: module() | atom(),
          columns: list(atom()),
          indexes: list(atom()),
          dataType: :set | :ordered_set | :bag | :duplicate_bag,
          copyType: :multi | :single
        }
      end

  - `:tableName` The name that will be used when creating the Mnesia table.

  - `:columns` The columns that will be used to create the Mnesia table.
      The first item in the list will be considered the `key` for the record

  - `:indexes` Defines additional columns that need to be indexed.
      By default, the key for the record is indexed.
      Adding the key column to the list will result in an error for Mnesia.

  - `:dataType` This is the type of Mnesia table we are creating.
      The types allowed are the same ones supported by Mnesia.

  - `:copyType` This defines if the DistrServer should copy the table to the local memory of the node.
      By default, if the DistrServer creates the Mnesia table, it will always be saved to memory.
      This option comes into effect when the DistrServer is joining an existing cluster where this role is already hosted.
      If your DistrServer is set to subscribe to the mnesia table, it will be copied to memory as is required by Mnesia.
      If you are not subscribing, your options are `:single` and `:multi`.

      - `:single` will only keep the table in the memory of the original node.
      This mode is dangerous as losing the original node will result in both data loss, and potential corruption.
      In the event of a failover in this mode, the failing over DistrServer will **not** run `create_action/1` as the table will be marked as created.

      - `:multi` will copy the table to the local memory of any node running the DistrServer.
      This mode is recommended for most use cases.
      Please check into how Mnesia operations (transaction or dirty) work so you use this most efficiently.
      Failure to do so may lead to poor write performance.

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
  - `:single` -> Copies are only on the table-creating-node.
  - `:multi` -> Copies are pushed to ALL nodes in the cluster.
  """
  @type copyTypes() :: :single | :multi
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
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # CALL BACKS
  #

  #
  #
  @doc """
  **-Callback required-**\n
  `DistrServer` configuration. See `distrConfig()` type for more information on the return.
  """
  @callback config() :: distrConfig()

  #
  #
  @doc """
  **-Callback required-**\n
  Entry point for the `DistrServer` process. Similar to `init/1` for GenServers.
  """
  @callback entry_point(var :: any()) ::
              {:ok, state :: any()}
              | {:ok, state :: any(),
                 timeout() | :hibernate | {:continue, continue_arg :: term()}}
              | :ignore
              | {:stop, reason :: term()}

  #
  #
  @doc """
  **-Callback required-**\n
  Callback that is triggered when the process creates the Mnesia Table for the cluster.
  """
  @callback create_action(tableConfig :: MnesiaTools.tableConfig()) :: :ok

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # `USE` MACRO
  #

  @doc false
  defmacro __using__(subscribe?: subscribe) do
    #
    #
    quote do
      # force this modules behavior
      @behaviour Beethoven.DistrServer
      # Imports GenServer behaviors
      use GenServer
      # Imports mnesiaTools
      import Beethoven.MnesiaTools
      require Logger

      #
      #
      #
      def config() do
        %{
          tableName: __MODULE__.Tracker,
          columns: [:col0, :col1, :col2],
          indexes: [],
          dataType: :set,
          copyType: :single
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
              {:ok, _node} = :mnesia.subscribe({:table, tableName, :detailed})

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
      # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
      #
      # Mnesia table tools.
      #

      #
      #
      @doc """
      Returns the name of the DistrServer `#{__MODULE__}`'s mnesia table.
      """
      @spec get_table_name() :: module() | atom()
      def get_table_name() do
        config() |> Map.get(:tableName)
      end

      #
      #
      @doc """
      Subscribes to the table mapped to the DistrServer `#{__MODULE__}`'s mnesia table.

      # Matches based on subscription

      ## `:simple`

          {:mnesia_table_event, {:atom, record(), _op_data}}

      ## `:detailed`

          {:mnesia_table_event, {:atom, module() | :atom(), record(), [] | [record()], _op_data}}

      """
      @spec subscribe(:simple | :detailed) :: :ok
      def subscribe(type \\ :simple) do
        _ = :mnesia.subscribe({:table, get_table_name(), type})
        :ok
      end

      #
      #
      @doc """
      Fetches all records from the DistrServer `#{__MODULE__}`'s mnesia table.
      """
      @spec fetch_all() :: list(tuple()) | list()
      def fetch_all() do
        tableName = get_table_name()

        :mnesia.dirty_select(tableName, [
          {:mnesia.table_info(tableName, :wild_pattern), [], [:"$_"]}
        ])
      end

      #
      #
      @doc """
      Fetches data from the DistrServer `#{__MODULE__}`'s mnesia table.
      Uses a record key to query the data. Will return all matching records.
      """
      @spec fetch(any()) :: list(tuple()) | list()
      def fetch(key) do
        :mnesia.dirty_read(get_table_name(), key)
      end

      #
      #
      @doc """
      Similar to `:mnesia.dirty_select/2` but only needs the match spec as an argument.
      The table name of the DistrServer `#{__MODULE__}`'s mnesia table is input automatically as the 1st arity.
      """
      @spec dirty_select(:ets.match_spec()) :: list(tuple) | list()
      def dirty_select(matchSpec) do
        :mnesia.dirty_select(get_table_name(), matchSpec)
      end

      #
      #
      @doc """
      Checks if the DistrServer `#{__MODULE__}`'s mnesia table exists.
      """
      @spec table_exists?() :: boolean()
      def table_exists?() do
        MnesiaTools.table_exists?(get_table_name())
      end

      #
      #
      @doc """
      Holds the thread until the DistrServer `#{__MODULE__}`'s mnesia table becomes available, or timeout occurs.
      Defaults to `1_000` milliseconds for timeouts and `15` milliseconds for checking intervals.
      """
      @spec until_exists() :: :ok | {:error, :timeout}
      def until_exists(int \\ 15, timeout \\ 1_000, acc \\ 0) do
        table_exists?()
        |> case do
          true ->
            :ok

          false ->
            if acc >= timeout do
              # acc is larger or equal to the timeout
              {:error, :timeout}
            else
              Process.sleep(int)
              until_exists(timeout, acc + int)
            end
        end
      end

      #
      #
    end

    #
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
