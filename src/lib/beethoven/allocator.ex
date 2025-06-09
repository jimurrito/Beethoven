defmodule Beethoven.Allocator do
  @moduledoc """
  Set of modules for handling allocation of work between cluster nodes.
  """

  alias Beethoven.Allocator

  use Supervisor

  def start_link(_opt) do
    children = [
      # Tracker DistrServer
      Allocator.Tracker,
      # Ingress server for signal. Sets signals to cruncher.
      Allocator.Ingress,
      # Cruncher to aggregate data and set a score for the current node.
      Allocator.Cruncher
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end

  #
  #
  @impl true
  def init(_init_arg) do
    :ignore
  end
end
