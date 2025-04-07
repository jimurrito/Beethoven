defmodule Beethoven.Role.Client do
  @moduledoc """
  Client library for accessing and communicating with the Role Server.
  """

  alias Beethoven.Utils
  alias Beethoven.Role, as: RoleServer

  #
  #
  @doc """
  Adds a role to the Role server. Role must already be defined in the config.
  The same as `add_role/1` but ran on an external node.
  """
  @spec add_role_remote(atom(), node()) :: :assigned | {:error, :timeout | any()}
  def add_role_remote(role, nodeName) do
    Utils.remote_call(fn -> add_role(role) end, nodeName)
  end

  #
  #
  @doc """
  Adds a role to the Role server. Role must already be defined in the config.
  """
  @spec add_role(atom()) :: :assigned | {:error, any()}
  def add_role(role) do
    GenServer.call(RoleServer, {:add_role, role})
  end

  #
  #
  @doc """
  Removes a role from the Role server.
  The same as `kill_role/1` but ran on an external node.
  """
  @spec kill_role_remote(atom(), node()) :: :dead | {:error, :timeout | :not_here}
  def kill_role_remote(role, nodeName) do
    Utils.remote_call(fn -> kill_role(role) end, nodeName)
  end

  #
  #
  @doc """
  Removes a role from the Role server.
  """
  @spec kill_role(atom()) :: :dead | {:error, :not_here}
  def kill_role(role) do
    GenServer.call(RoleServer, {:add_role, role})
  end
end
