defmodule Beethoven do
  @moduledoc """
  Documentation for `Beethoven`.
  """

  def start_link(_args) do
    children = [
      # Core GenServer
      Beethoven.Core
    ]
    opts = [strategy: :one_for_one, name: Beethoven.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
