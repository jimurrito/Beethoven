defmodule Beethoven.HwMonSignals do
  @moduledoc false

  use Beethoven.Allocator.Agent

  #
  # CPU %
  signal(name: :cpu, weight: 1.0, type: :percent)

  #
  # Ram %
  signal(name: :ram, weight: 1.0, type: :percent)
end
