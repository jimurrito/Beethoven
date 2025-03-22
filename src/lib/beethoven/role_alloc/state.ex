defmodule Beethoven.RoleAlloc.State do
  @moduledoc """
  State struct for RoleAlloc server
  """

  defstruct [:roles, :queue, :ready?]


end
