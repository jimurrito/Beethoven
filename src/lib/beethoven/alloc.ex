defmodule Beethoven.Alloc do
  @moduledoc """
  Set of modules for handling allocation of work between cluster nodes.
  """

  alias Beethoven.Alloc

  def start_link(_opt) do
    children = [
      # Dispatch server for allocation requests
      Alloc.Dispatch,
      # Ingress server for signal. Sets signals to cruncher.
      Alloc.Ingress,
      # Cruncher to aggregate data and set a score for the current node.
      Alloc.Cruncher
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end
end
