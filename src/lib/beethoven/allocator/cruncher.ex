defmodule Beethoven.Allocator.Cruncher do
  @moduledoc """
  Crunches signal data and generates an allocation score for the current node.
  """

  require Logger
  use GenServer

  alias Beethoven.Allocator.Tracker, as: AllocTracker
  alias Beethoven.Allocator.Ingress.Cache, as: IngressCache

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
    Logger.debug(operation: :check)

    #
    # Get all records and create a score
    score =
      :ets.select(IngressCache, [
        {{:"$1", :"$2", :"$3", :"$4"}, [], [:"$_"]}
      ])
      # Algorithm per item
      |> Enum.map(&algorithm/1)
      # Sum the values in the list
      # This will be the score
      |> Enum.sum()

    #
    Logger.info(new_busy_score: score, node: node())

    # Write to mnesia
    :ok = :mnesia.dirty_write({AllocTracker, node(), score, DateTime.now!("Etc/UTC")})
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
  @doc """
  Crunching algorithm for each signal item.

  REPLACE WITH SOMETHING BETTER LATER

  """
  def algorithm({_name, weight, _type, data}) do
    :math.log(data) * weight
  end

  #
  #
end
