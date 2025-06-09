defmodule Beethoven.Allocator.Tools do
  @moduledoc false

  #
  #
  @doc """
  Creates an ETS table.
  """
  @spec make_ets(atom() | module(), list(atom())) :: :ok
  def make_ets(table, opts \\ [:set, :public, :named_table]) do
    ^table = :ets.new(table, opts)
    :ok
  end

  #
  #
end
