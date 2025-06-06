defmodule Beethoven.Alloc.Test do
  @moduledoc false
  use Beethoven.Alloc.Agent

  signal(name: :http_requests, weight: 10, type: :percent)
  signal(name: :http_requests, weight: 8, type: :count)

  #
end
