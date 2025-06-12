defmodule Beethoven.Application do
  @moduledoc false
  alias Beethoven.Utils

  use Application

  @impl true
  @spec start(any(), any()) :: {:error, any()} | {:ok, pid()}
  def start(_type, _args) do
    if !Utils.get_app_env(:enabled, true) do
      # should not be started
      {:ok, self()}
    else
      #
      # Start Mnesia service on the node.
      :ok = :mnesia.start()
      #
      children = [
        # Ready tracker
        Beethoven.Ready,
        # Azure aware genserver. Monitors IMDS.
        Beethoven.Az,
        # Locator GenServer
        # Entry point for beethoven
        # Once seeking is complete, it will spawn multiple core services to this Supervisor.
        Beethoven.Locator
      ]

      # Disables restarts for the services.
      opts = [strategy: :one_for_one, name: Beethoven.RootSupervisor]
      Supervisor.start_link(children, opts)
    end
  end
end
