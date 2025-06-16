defmodule Beethoven.RoleMgmt do
  @moduledoc """
  The RoleMgmt stack is a collective of servers responsible for the management and allocation of specialized OTP complaint PIDs.
  These specialized PIDs are referred to as roles.
  Roles are defined in in the application config for `:beethoven`.

  ## Example

      config :beethoven,
        ...
        roles: [
          # {<AtomName>, <Module>, <Initial Args>, <InstanceCount>}
          {:test, Beethoven.TestRole, [arg1: "arg1"], 1}
        ]

  Based on the definition for each role, the nodes in the `Beethoven` cluster will ensure the required amount of that service is running across the cluster.
  The number of service instances needed for the role is defined with the `InstanceCount` element in the tuple.
  These services are spread across the cluster based on the busyness of the nodes. Busyness is determined by `Beethoven.Allocator`.

  In the event of a node failure, the stack will react and re-distribute the roles to the remaining nodes in the cluster.
  If a new/previous node comes online in the cluster, role assignment evaluation will be triggered to ensure the correct amount of roles are allocated.
  As of now, roles are not balanced after they are assigned. Once the node is running a role, it runs it until it shuts down.

  """

  require Logger
  use Supervisor

  alias __MODULE__, as: RMgmt

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Supervisor functions
  #

  #
  #
  @doc """
  Supervisor Entry point.
  """
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(init_args \\ []) do
    Supervisor.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  #
  #
  @impl true
  def init(_init_arg) do
    Logger.info(status: :startup)

    children = [
      # Role PID Dynamic Supervisor
      RMgmt.Manager,
      # Role Assignment server
      RMgmt.Assign,
      # Role failover server
      RMgmt.Failover
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
