defmodule Template.GenServerEts do
  @moduledoc """
  """

  require Logger
  use GenServer

  alias __MODULE__.Table, as: ModTable

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # GenServer callback functions
  #

  #
  #
  @doc """
  Supervisor Entry point.
  """
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(init_args \\ []) do
    GenServer.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  #
  #
  @impl true
  def init(_init_arg) do
    Logger.info(status: :startup)
    _ = :ets.new(ModTable, [:set, :public, :named_table])
    Logger.info(status: :startup_complete)
    {:ok, :ok}
  end

  #
  #
end
