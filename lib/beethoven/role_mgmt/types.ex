defmodule Beethoven.RoleMgmt.Types do
  @moduledoc false

  #
  #
  @typedoc """
  Simplified type for tracker records.
  Just excludes the table name from the record tuple.
  """
  @type roleRecord() ::
          {roleName :: atom(), roleModule :: module(), args :: any(), instances :: integer()}
  #
  #
  @typedoc """
  Role list in the form of a map.
  """
  @type roleMap() :: map()

  #
  #
end
