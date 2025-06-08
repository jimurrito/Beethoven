defmodule Beethoven.Alloc.Cruncher do
  @moduledoc """
  Crunches signal data and generates an allocation score for the current node.
  """

  require Logger
  use GenServer

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
    Logger.info(status: :startup_complete)
    {:ok, :ok}
  end

  #
  #
  @impl true
  def handle_cast(:check, :ok) do
    #
    # - Pull data from ETS
    # - Aggregate data
    # - Push score to Mnesia
    #
    {:noreply, :ok}
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Public API functions
  #

  #
  #
  @doc """
  Sends a check message to the local instance of Cruncher
  """
  @spec send_check() :: :ok
  def send_check() do
    GenServer.cast(__MODULE__, :check)
  end

  #
  #
end
