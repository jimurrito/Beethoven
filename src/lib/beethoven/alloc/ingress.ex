defmodule Beethoven.Alloc.Ingress do
  @moduledoc """
  GenServer to handle ingress of signal data.
  """

  require Logger
  use GenServer

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # types
  #

  #
  @typedoc """

  """
  @type signal_message() :: {header :: signal_header(), payload :: signal_payload()}

  #
  @typedoc """

  """
  @type signal_header() :: {name :: atom(), weight :: integer(), type :: atom()}

  #
  @typedoc """

  """
  @type signal_payload() :: any()

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
    #
    # - CREATE ETS TABLE IF NEEDED
    #
    Logger.info(status: :startup_complete)
    {:ok, :ok}
  end

  #
  #
  @impl true
  def handle_cast({:signal, payload}, :ok) do
    IO.inspect(allocator_signal: payload)
    #
    # - 
    #
    #
    #
    #
    {:noreply, :ok}
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # callbacks for agents functions
  #

  #
  #
  @doc """
  Sends a signal message to Allocator

      {header :: {name :: atom(), weight :: integer(), type :: atom()}, payload :: signal_payload()}
  """
  @spec send_signal(signal_message()) :: :ok
  def send_signal(signal) do
    GenServer.cast(__MODULE__, {:signal, signal})
  end

  #
end
