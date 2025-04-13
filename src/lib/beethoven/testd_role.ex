defmodule Beethoven.TestdRole do
  @moduledoc """
  Example role that leverages DistrServer instead of GenServer.
  """

  require Logger
  alias Beethoven.DistrServer
  use DistrServer

  #
  #
  @impl true
  def config() do
    %{
      tableName: Beethoven.TestdRole.Mnesia,
      columns: [:name1, :name2],
      indexes: [:name1],
      dataType: :ordered_set,
      copyType: :local,
      subscribe?: true
    }
  end

  #
  #
  def start_link(init_args) do
    # Starts genserver and executes creation of Mnesia in the callers context.
    DistrServer.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  #
  # Similar to `init/1` callback
  @impl true
  def entry_point(init_args) do
    #
    IO.inspect(
      {:test_distributed_role_running, {TestdRole, [args: init_args]}}
    )

    #
    {:ok, :ok}
  end

  #
  #
  @impl true
  def create_action() do
    :ok
  end
end
