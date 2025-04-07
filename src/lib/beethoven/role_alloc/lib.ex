defmodule Beethoven.RoleAlloc.Lib do
  @moduledoc """
  Library module for RoleAlloc server.
  """

  require Logger
  alias Beethoven.Tracker

  #
  #
  #
  @doc """
  Makes fresh retries tuple.
  retries have 4 categories
  0 -> Role retries
  1 -> Total retries
  2 -> Max Role retries (# of nodes via Node.list/0)
  3 -> Max Total Retries (all roles * all hosts)
  """
  def get_new_retries(roles) do
    {0, 0, Node.list(), get_max_retries(roles)}
  end

  #
  #
  #
  @doc """
  Gets the maximum number of retries possible.
  Based on `total roles to assign * number of nodes` in the cluster via `Node.list/0`.

  If result equals <4 output value will be 4.
  """
  @spec get_max_retries(map()) :: integer()
  def get_max_retries(roles) do
    max = length(role_map_to_list(roles)) * length(Node.list())

    # Ensures fn returns at least 4
    cond do
      max < 4 -> 4
      true -> max
    end
  end

  #
  #
  #
  @doc """
  Takes input role map and provides a list of roles needed based on current roles hosted in the cluster.
  """
  @spec get_open_roles(map()) :: list()
  def get_open_roles(roles) do
    # role_list represents lists that are needed according to the runtime config provided in config.exs.
    # get roles by key - will de duplicate if multiple instances are needed
    # converts the list of maps from config to a list of atoms
    role_list = role_map_to_list(roles)
    # Filter what roles are needed based on what is in mnesia.
    # Essentially removes roles hosted on Mnesia from the ones needed in the config.
    Tracker.find_work(role_list)
  end

  #
  #
  #
  @doc """
  Takes the input role map and outputs a list of roles.
  Uses the instance value for each role to create `n` amount of roles in the list as needed,
  """
  @spec role_map_to_list(map()) :: list()
  def role_map_to_list(roles) do
    roles
    |> Enum.map(fn {name, {_mod, _args, inst}} ->
      # range to create multiple instances
      1..inst
      |> Enum.map(fn _ -> name end)
    end)
    # Flatten list
    |> List.flatten()
  end

  #
  #
  #
  @doc """
  Generates a new host queue based on how many roles the nodes have.
  Less roles == higher priority in the queue.
  """
  @spec make_host_queue() :: :queue.queue(node())
  def make_host_queue() do
    Tracker.get_active_roles_by_host()
    # sort by amount of jobs held
    |> Enum.sort_by(fn [_node, roles] -> length(roles) end)
    # Return list of only hosts
    |> Enum.map(fn [node, _roles] -> node end)
    |> :queue.from_list()
  end
end
