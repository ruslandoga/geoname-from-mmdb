defmodule MTest do
  use ExUnit.Case
  doctest M

  test "greets the world" do
    assert M.hello() == :world
  end
end
