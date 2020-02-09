defmodule TringinTest do
  use ExUnit.Case
  doctest Tringin

  test "greets the world" do
    assert Tringin.hello() == :world
  end
end
