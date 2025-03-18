defmodule Beethoven.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Core GenServer
      Beethoven.Core
    ]

    opts = [strategy: :one_for_one, name: Beethoven.RootSupervisor]
    Supervisor.start_link(children, opts)
  end
end
