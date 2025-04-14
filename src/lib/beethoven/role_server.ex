defmodule Beethoven.RoleServer do
  @moduledoc """
  Server PID that manages role assignment across the cluster.
  Leveraging the Mnesia integration with `DistrServer`,
  these processes will be ephemeral and keep all state within Mnesia.
  """
  require Logger
  alias Beethoven.DistrServer
  alias Beethoven.RoleUtils

  use DistrServer

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # DistrServer callback functions
  #

  #
  #
  @doc """
  Supervisor Entry point.
  """
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(init_args \\ []) do
    DistrServer.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  #
  #
  @impl true
  def config() do
    %{
      tableName: __MODULE__.Tracker,
      columns: [:role, :count, :assigned, :workers, :last_change],
      indexes: [:role],
      dataType: :ordered_set,
      copyType: :multi,
      subscribe?: true
    }
  end

  #
  # Setup table with all the roles defined in `config.exs`
  @impl true
  def create_action({tableName, _columns, _indexes, _dataType, _copyType}) do
    # fn to setup table with initial data
    {:atomic, :ok} =
      fn ->
        # Lock entire table to ensure no other transaction could jump in.
        # _ = :mnesia.lock_table(tableConfig.tableName, :read)
        # Get Roles from config
        RoleUtils.get_role_config()
        |> Enum.each(
          # Add roles to table
          fn {name, {_mod, _args, inst}} ->
            # {MNESIA_TABLE, role_name, count, assigned, workers, last_changed}
            :mnesia.write({tableName, name, inst, 0, [], DateTime.now!("Etc/UTC")})
          end
        )
      end
      |> :mnesia.transaction()

    :ok
  end

  #
  #
  @impl true
  def entry_point(_var) do
    Logger.info(status: :startup)
    Logger.info(status: :startup_complete)
    {:ok, :ok}
  end
end
