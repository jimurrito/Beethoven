defmodule Beethoven.RoleAlloc do
  @moduledoc """
  Role Allocation Server. Works as a queue to assign roles needed by the configuration.
  """

  use GenServer
  require Logger

  def start_link do
    GenServer.start_link(__MODULE__, [], [])
  end

  @impl true
  def init(_arg) do
    #
    # get roles from config.exs
    roles =
      Application.fetch_env(:beethoven, :roles)
      |> case do
        {:ok, value} ->
          value

        :error ->
          Logger.notice(":roles is not set in config/*.exs. Assuming no roles.")
          []
      end

    #
    #
    {:ok, {:initializing, roles}}
  end
end
