defmodule Beethoven.Core.Transition do
  @moduledoc """
  Library to reduce code length of Core server.
  Handles logic for mode transitions
  """

  require Logger
  alias Beethoven.RoleAlloc
  alias Beethoven.Core.Listener
  alias Beethoven.Role, as: RoleServer

  #
  #
  @spec transition(atom(), atom()) :: :ok | :noop
  def transition(mode, new_mode) do
    case new_mode do
      # is same mode
      ^mode ->
        :noop

      # changing modes
      :standalone ->
        Logger.info("Transitioning server modes: [#{mode}] => [#{new_mode}]")
        to_standalone()

      :clustered ->
        Logger.info("Transitioning server modes: [#{mode}] => [#{new_mode}]")
        to_clustered()
    end
  end

  #
  #
  # Converts service from clustered to standalone
  @spec to_standalone() :: :ok
  defp to_standalone() do
    # Starts all 3 servers
    start_servers()
  end

  #
  #
  # Converts service from standalone to clustered
  @spec to_clustered() :: :ok
  defp to_clustered() do
    # Role Allocation Server
    :ok = RoleAlloc.async_start()
    #
    # Room for additional logic. *If needed.*
    #
    :ok
  end

  #
  #
  #
  @doc """
  Starts all 3 dependant services for `Beethoven.Core`
  """
  @spec start_servers() :: :ok
  def start_servers() do
    [:ok, :ok, :ok] = [
      Listener.async_start(),
      RoleServer.async_start(),
      RoleAlloc.async_start()
    ]

    # return atom
    :ok
  end

  #
  #
end
