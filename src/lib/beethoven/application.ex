defmodule Beethoven.Application do
  @moduledoc false

  use Application

  @impl true
  @spec start(any(), any()) :: {:error, any()} | {:ok, pid()}
  def start(_type, _args) do
    #
    # Start Mnesia service on the node.
    :ok = :mnesia.start()
    #
    children = [
      # Azure aware genserver. Monitors IMDS.
      Beethoven.Az,
      # Locator GenServer
      # Entry point for beethoven
      # Once seeking is complete, it will spawn `Core` to this Supervisor.
      Beethoven.Locator,
      # Allocator service
      # accepts signals from agents to determine how busy a node is.
      Beethoven.Alloc
    ]

    # Disables restarts for the services.
    opts = [strategy: :one_for_one, name: Beethoven.RootSupervisor]
    Supervisor.start_link(children, opts)
  end
end
