defmodule Beethoven.Allocator.Test do
  @moduledoc false
  use Beethoven.Allocator.Agent

  signal(name: :ram, weight: 10.0, type: :percent)
  signal(name: :http_requests, weight: 8.0, type: :count)

  #
end
