defmodule Beethoven do
  @moduledoc """
  A Decentralized failover and peer-to-peer node finder for Elixir.
  Allows Elixir nodes to find each other automatically.
  Once connected, they can coordinate to delegate roles and tasks between the nodes in the cluster.
  Written using only the Elixir and Erlang standard library.

  This module acts as the unified client for interacting with beethoven as an external client.
  Avoid using the other modules for external PID calls to beethoven services.
  """
  
  alias Beethoven.Role.Client, as: RoleClient
  alias Beethoven.RoleAlloc.Client, as: RoleAlloc

  #
  #
  @doc """
  Kills the an Elixir/Erlang application running Beethoven.
  """
  @spec kill_node() :: :ok
  def kill_node() do
    # Prune self from Tracker via RoleAlloc Server
    :ok = RoleAlloc.prune()
    # Kill all roles on the RoleServer
    :ok = RoleClient.kill_all_roles()
    # Kills ErlangVM
    :ok = :init.stop()
  end

  #
  #
end
