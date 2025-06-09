defmodule Beethoven.Ready do
  @moduledoc """
  Simple PID to track when Beethoven has fully initialized.
  Usually just called from RoleServer when it has ran out of work.
  """

  require Logger
  use GenServer

  alias __MODULE__.Table, as: RTable

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
    _ = :ets.new(RTable, [:set, :public, :named_table])
    true = :ets.insert(RTable, {:ready?, false, DateTime.now!("Etc/UTC")})
    Logger.info(status: :startup_complete)
    {:ok, :ok}
  end

  #
  #
  @impl true
  def handle_cast(:ready, state) do
    true = :ets.insert(RTable, {:ready?, true, DateTime.now!("Etc/UTC")})
    {:noreply, state}
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Public API functions
  #

  #
  #
  @doc """
  Gets the current ready state for Beethoven.
  """
  @spec ready?() :: boolean()
  def ready?() do
    [{:ready?, ready_state, _}] = :ets.lookup(RTable, :ready?)
    ready_state
  end

  #
  #
  @doc """
  Similar to `ready?()` but will block until the service is ready.
  Defaults to 5_000 milliseconds.
  """
  @spec until_ready(integer()) :: :ok | :timeout
  def until_ready(timeout \\ 5_000) do
    until = DateTime.add(DateTime.now!("Etc/UTC"), timeout, :millisecond)
    until_ready(until, false)
  end

  # when state is false
  defp until_ready(until, false) do
    DateTime.after?(DateTime.now!("Etc/UTC"), until)
    |> if do
      # we have timed out
      :timeout
    else
      # not timed out yet
      # check and recurse
      until_ready(until, ready?())
    end
  end

  # when ready is true
  defp until_ready(_until, true) do
    :ok
  end

  #
  #
  @doc """
  Sets ready state for Beethoven. Setting this value to true will make `ready?()` return true; indicating the service has initialized.
  Setting `false` performs the opposite.
  """
  @spec set_ready(boolean()) :: :ok
  def set_ready(ready_state) do
    Logger.info(beethoven_ready_status: ready_state)
    true = :ets.insert(RTable, {:ready?, ready_state, DateTime.now!("Etc/UTC")})
    :ok
  end

  #
end
