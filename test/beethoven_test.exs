defmodule BeethovenTest do
  use ExUnit.Case
  doctest Beethoven

  test "greets the world" do
    assert Beethoven.hello() == :world
  end
end
