defmodule Beethoven.Alloc.Ingress do
  @moduledoc """
  GenServer to handle ingress of signal data.
  """

  require Logger
  use GenServer

  # alias Beethoven.Alloc.Tools
  alias Beethoven.Alloc.Cruncher
  alias __MODULE__.Cache, as: IngressCache
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
  @type signal_header() :: {name :: atom(), weight :: float(), type :: atom()}

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
    _ = :ets.new(IngressCache, [:set, :public, :named_table])
    Logger.info(status: :startup_complete)
    {:ok, :ok}
  end

  #
  # Send cast into a continue
  @impl true
  def handle_cast({:signal, payload}, :ok) do
    {:noreply, :ok, {:continue, {:process_signal, payload}}}
  end

  #
  #
  @impl true
  def handle_continue({:process_signal, {{name, weight, type}, payload}}, state) do
    #
    Logger.debug(
      operation: :signal_received,
      signal: name,
      weight: weight,
      type: type,
      payload: payload
    )

    #
    # Set to ETS based on type
    true =
      case type do
        # when signal is count
        :count ->
          # get record
          [{^name, ^weight, ^type, data}] = :ets.lookup(IngressCache, name)
          # set into ETS
          :ets.insert(IngressCache, {name, weight, type, data + payload})

        # all other signals
        type ->
          # set into ETS
          :ets.insert(IngressCache, {name, weight, type, payload})
      end

    #
    # Send alert to `Alloc.Cruncher`
    :ok = Cruncher.send_check()

    #
    {:noreply, state}
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # callbacks for agents functions
  #

  #
  #
  @doc """
  Sends a signal message to `Alloc.Ingress`

      {header :: {name :: atom(), weight :: integer(), type :: atom()}, payload :: signal_payload()}
  """
  @spec send_signal(signal_message()) :: :ok
  def send_signal(signal) do
    GenServer.cast(__MODULE__, {:signal, signal})
  end

  #
  #
end
