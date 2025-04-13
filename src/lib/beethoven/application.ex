defmodule Beethoven.Application do
  @moduledoc false

  use Application

  @impl true
  @spec start(any(), any()) :: {:error, any()} | {:ok, pid()}
  def start(_type, _args) do
    children = [
      # Azure aware genserver. Monitors IMDS.
      Beethoven.Az,
      # Core GenServer
      # Entry point for beethoven
      Beethoven.Core,
      #
      #Beethoven.TestdRole
    ]

    # Disables restarts for the services.
    opts = [strategy: :one_for_one, name: Beethoven.RootSupervisor, max_restarts: 0]
    Supervisor.start_link(children, opts)
  end
end
