defmodule Beethoven.Signals do
  @moduledoc """
  Beethoven Allocator signals for the Beethoven service itself.
  """

  # ex:
  # - signal(name: :ram, weight: 10.0, type: :percent)
  # - signal(name: :http_requests, weight: 8.0, type: :count)
  #

  use Beethoven.Allocator.Agent

  #
  # When a node uses starts hosting a role
  signal(name: :beethoven_role, weight: 5.0, type: :count)

  #
  #

end
