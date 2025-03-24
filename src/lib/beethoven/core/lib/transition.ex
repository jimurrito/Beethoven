defmodule Beethoven.Core.Lib.Transition do
  @moduledoc """
  Library to reduce code length of Core server.
  Handles logic for mode transitions
  """

  require Logger
  alias Beethoven.RoleAlloc
  alias Beethoven.Listener
  alias Beethoven.Role, as: RoleServer
  alias Beethoven.Core.TaskSupervisor, as: CoreSupervisor

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
    # TCP Listener
    _ = Task.Supervisor.start_child(CoreSupervisor, fn -> Listener.start([]) end)
    # Role manager
    _ = Task.Supervisor.start_child(CoreSupervisor, fn -> RoleServer.start([]) end)
    # Role Allocation Server
    _ = Task.Supervisor.start_child(CoreSupervisor, fn -> RoleAlloc.start([]) end)
    #
    :ok
  end

  #
  #
  # Converts service from standalone to clustered
  @spec to_clustered() :: :ok
  defp to_clustered() do
    # Role Allocation Server
    _ = Task.Supervisor.start_child(CoreSupervisor, fn -> RoleAlloc.start([]) end)
    #
    :ok
  end

  #
  #
end
