defmodule Beethoven do
  @moduledoc """
  Documentation for `Beethoven`.
  """

  
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link(_args) do
    children = [
      # Core GenServer
      Beethoven.Core
    ]

    opts = [strategy: :one_for_one, name: Beethoven.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
