defmodule Beethoven.RoleMgmt.Manager do
  @moduledoc """
  Dynamic supervisor that manages the specialized role PIDs.

  # Public API
  - `add_role/3` Adds a role to the Manager Dynamic Supervisor. Stores role name + PID in ETS.
  - `remove_role/1` Removes a hosted role from the Dynamic Supervisor.

  The use of ETS is just for tracking atomic role names to PIDs.
  It has no awareness of the cluster level allocations for this role.

  """

  require Logger
  use DynamicSupervisor

  alias Beethoven.Signals
  alias __MODULE__.Table, as: ManagerTable

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # DynamicSupervisor functions
  #

  #
  #
  @doc """
  Supervisor Entry point.
  """
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(init_args \\ []) do
    DynamicSupervisor.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  #
  #
  @impl true
  def init(_init_arg) do
    Logger.info(status: :startup)
    _ = :ets.new(ManagerTable, [:set, :public, :named_table])
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Public API functions
  #

  #
  #
  @doc """
  Adds a role to the `#{__MODULE__}` Dynamic Supervisor. Adds the pid + roleName to ETS for tracking.
  If the role already exists, `:ok` will still be returned.
  """
  @spec add_role(atom(), module(), any()) :: :ok
  def add_role(roleName, roleModule, args) do
    Logger.info(operation: :add_role, role: roleName, role_mod: roleModule)
    # Check if the role is already running
    :ets.lookup(ManagerTable, roleName)
    |> case do
      # not running
      [] ->
        {:ok, pid} = DynamicSupervisor.start_child(__MODULE__, {roleModule, args})
        Signals.increment_beethoven_role_count()
        true = :ets.insert(ManagerTable, {roleName, pid, DateTime.now!("Etc/UTC")})
        #
        :ok

      # running on the node
      _ ->
        :ok
    end
  end

  #
  #
  @doc """
  Removes the role from the `#{__MODULE__}`Dynamic Supervisor.
  """
  @spec remove_role(atom()) :: :ok | {:error, :not_found}
  def remove_role(roleName) do
    :ets.lookup(ManagerTable, roleName)
    |> case do
      [{^roleName, pid, _}] ->
        result = DynamicSupervisor.terminate_child(__MODULE__, pid)
        Signals.decrement_beethoven_role_count()
        result

      [] ->
        {:error, :not_found}
    end
  end

  #
  #
end
