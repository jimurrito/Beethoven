defmodule Beethoven.Alloc.Dispatch do
  @moduledoc """
  Dispatches the URI of the node with the least amount of work.
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
    Logger.info(status: :startup)
    Logger.info(status: :startup_complete)
    {:ok, :ok}
  end

  #
  #
  # Call to get a node to allocate work to.
  @impl true
  def handle_call(:allocate, _from, state) do
    #
    # - Pull all data from Mnesia
    # - return node with the lowest score to the caller
    #
    {:reply, nil, state}
  end

  #
  #
end
