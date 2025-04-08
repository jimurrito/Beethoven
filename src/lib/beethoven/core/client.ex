defmodule Beethoven.Core.Client do
  @moduledoc """
  Client library for accessing or interacting with the `Beethoven.Core` server.
  """

  alias Beethoven.Role.Client, as: RoleClient
  alias Beethoven.Core
  alias Beethoven.RoleAlloc.Client, as: RoleAlloc

  #
  #
  @doc """
  Kills Beethoven Core and dependency tree gracefully.
  """
  @spec start_shutdown() :: :ok
  def start_shutdown() do
    # Prune self from Tracker via RoleAlloc Server
    :ok = RoleAlloc.prune()
    # Kill all roles on the RoleServer
    :ok = RoleClient.kill_all_roles()
    #
    :ok
  end

  #
  #
  @doc """
  Triggers a standalone transition for `Beethoven.Core`.
  Returns `:noop` if Core Server is already in the desired state.
  """
  @spec to_standalone() :: :ok | :noop
  def to_standalone() do
    GenServer.call(Core, {:transition, :standalone})
  end

  #
  #
  @doc """
  Triggers a clustered transition for `Beethoven.Core`.
  Returns `:noop` if Core Server is already in the desired state.
  """
  @spec to_clustered() :: :ok | :noop
  def to_clustered() do
    GenServer.call(Core, {:transition, :clustered})
  end
end
