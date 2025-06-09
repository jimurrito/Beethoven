defmodule Beethoven.Allocator.Dispatch do
  @moduledoc """
  Dispatches the URI of the node with the least amount of work.
  """

  require Logger
  use GenServer

  alias Beethoven.Allocator.Tracker, as: AllocTracker

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
    # Get all records
    {AllocTracker, node, score, _} =
      :mnesia.dirty_select(AllocTracker, [
        {{:"$1", :"$2", :"$3"}, [], [:"$_"]}
      ])
      # sort by score
      |> Enum.sort_by(&elem(&1, 2), :asc)
      # get only the first
      |> List.first()

    #
    Logger.debug(status: :allocation_requested, provided: node, score: score)

    #
    {:reply, node, state}
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Public API functions
  #

  #
  #
  @doc """
  Requests a node for work allocation.
  """
  @spec allocate() :: node()
  def allocate() do
    GenServer.call(__MODULE__, :allocate)
  end

  #
  #
end
