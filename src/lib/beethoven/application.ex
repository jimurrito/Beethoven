defmodule Beethoven.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Core GenServer
      # Entry point for beethoven
      Beethoven.Core
    ]

    # By default, will restart PIDs 3x before deciding the PID can stay dead.
    opts = [strategy: :one_for_one, name: Beethoven.RootSupervisor]
    Supervisor.start_link(children, opts)
  end
end
