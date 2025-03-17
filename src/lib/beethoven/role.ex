defmodule Beethoven.Role do
  @moduledoc """
  Handles role re/assignment between clusters.
  """

  use GenServer
  require Logger

  alias Beethoven.Core, as: BeeServer

  #
  #
  #
  #
  # Entry point for Supervisors
  def start_link(_args) do
    GenServer.start(__MODULE__, [], name: __MODULE__)
  end

  #
  #
  #
  #
  #
  @impl true
  def init(_args) do
    # Get application config for roles
    roles =
      Application.fetch_env(:beethoven, :roles)
      |> case do
        {:ok, value} ->
          value

        :error ->
          Logger.notice(":roles is not set in config/*.exs. Assuming no roles.")
          []
      end

    IO.inspect({:roles, roles})

    {:ok, roles}
  end

  #
  #
  #
  # Check role cast, but when we have no roles
  @impl true
  def handle_cast(:check, roles) when roles == [] do
    Logger.notice(
      "Role check was initiated for Beethoven.RoleServer, but there are no roles to track. Nothing to do."
    )

    {:noreply, roles}
  end

  #
  #
  @impl true
  def handle_cast(:check, roles) do
    {:noreply, roles}
  end

  #
  #
  #
  #
  #
  # Catch All handle_info
  # MUST BE AT BOTTOM OF MODULE FILE **WITHOUT THIS, COORDINATOR GENSERVER WILL CRASH ON UNMAPPED MSG!!**
  @impl true
  def handle_info(msg, state) do
    Logger.warning("[unexpected] Beethoven.RoleServer received an un-mapped message.")
    IO.inspect({:unmapped_msg, msg})
    {:noreply, state}
  end
end
