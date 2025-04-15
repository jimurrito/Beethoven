defmodule Beethoven.RoleUtils do
  @moduledoc false

  require Logger
  alias Beethoven.Utils

  #
  #
  @typedoc """
  Represents a single role definition.
  Same structure used to define the role within `config.exs`.
  """
  @type role() ::
          {name :: atom(), module :: module(), init_args :: list(any()), inst :: integer()}
  #
  #
  @typedoc """
  List of roles().
  """
  @type roles() :: list(role())
  #
  #
  @typedoc """
  Role list in the form of a map.
  """
  @type roleMap() :: map()

  #
  #
  #
  #
  @doc """
  Retrieves roles from config and converts to map.
  """
  @spec get_role_config() :: roleMap()
  def get_role_config() do
    # get roles from config.exs
    Utils.get_app_env(:roles, [])
    # converts to map
    |> role_list_to_map()
  end

  #
  #
  #
  @doc """
  Creates a map from a list of maps. First element of the map needs to be an atom.
  This same atom will be the key for the rest of the data in the map.
  """
  @spec role_list_to_map(roles()) :: roleMap()
  def role_list_to_map(role_list) do
    role_list_to_map(role_list, %{})
  end

  # End loop
  defp role_list_to_map([], state) do
    state
  end

  # Working loop
  defp role_list_to_map([{role_name, mod, args, inst} | role_list], state)
       when is_atom(role_name) do
    state = state |> Map.put(role_name, {mod, args, inst})
    role_list_to_map(role_list, state)
  end

  # Working loop - bad syntax for role manifest
  defp role_list_to_map([role_bad | role_list], state) do
    Logger.error(
      "One of the roles provided is not in the proper syntax. This role will be ignored.",
      expected: "{:role_name, Module, ['args'], 1}",
      received: role_bad
    )

    role_list_to_map(role_list, state)
  end

  #
  #
end
