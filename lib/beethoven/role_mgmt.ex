defmodule Beethoven.RoleMgmt do
  @moduledoc """
  The RoleMgmt stack is a collective of servers responsible for the management and allocation of specialized OTP complaint PIDs.
  These specialized PIDs are referred to as roles.
  Roles are defined in in the application config for `:beethoven`.
  To understand compatibility for using a module as a Beethoven role, please see the below section on **Role Compatibility**.

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

  # Role Compatibility

  Most OTP compliant PIDs are supported, but some caveats should be expected.
  The major caveat is that calls across the Beethoven cluster are not supported using the `GenServer` or `DistrServer` cast or calls.
  To communicate with these role PIDs across the Beethoven node level, you will need to use the erlang built-in `send/2` and `receive/1`.
  These functions do support calling PIDs across the cluster.

  Keeping this in mind, there is a workaround.
  Using a combination of the roles defined in RoleMgmt and `Beethoven.Utils.remote_call/3`,
  you can make any GenServer or DistrServer function needed.

  The `DistrServer` using modules were partially created for use with RoleMgmt.
  Keeping at least 2 instances of the DistrServer on the cluster helps ensure the data is resilient.
  However instances 3+ is recommended.

  If you want to put the role on all nodes, please avoid utilizing RoleMgmt.
  Instead use a supervisor or application to host the PID instead.

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
