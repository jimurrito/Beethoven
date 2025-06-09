defmodule Beethoven.Allocator.Ingress do
  @moduledoc """
  GenServer to handle ingress of signal data.
  Data sent to this Server is pushed into `:ets` for use by `Beethoven.Allocator.Cruncher`.
  """

  require Logger
  use GenServer

  alias Beethoven.Allocator.Types
  alias Beethoven.Allocator.Cruncher
  alias __MODULE__.Cache, as: IngressCache

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # types
  #

  #
  @typedoc """
  Message wrapper for sending payload to `Beethoven.Allocator.Ingress`.
  """
  @type signal_message() :: Types.signal_message()

  #
  @typedoc """
  Header for the signal metadata; when sending a signal to `Beethoven.Allocator.Ingress`.
  """
  @type signal_message_header() :: Types.signal_message_header()

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
          :ets.lookup(IngressCache, name)
          |> case do
            # record found
            [{^name, ^weight, ^type, data}] ->
              # combine old and new state
              new_data = data + payload
              # lower then 0 check
              new_data =
                cond do
                  # State is lower then 0.
                  new_data < 0 -> 0
                  # not lower -> return as is.
                  true -> new_data
                end

              :ets.insert(IngressCache, {name, weight, type, new_data})

            # not found
            [] ->
              :ets.insert(IngressCache, {name, weight, type, payload})
          end

        # all other signals
        type ->
          # set into ETS
          :ets.insert(IngressCache, {name, weight, type, payload})
      end

    #
    # Send alert to `Allocator.Cruncher`
    :ok = Cruncher.send_check()

    #
    {:noreply, state}
  end

  #
  #
end
