defmodule ExDatalogTest do
  use ExUnit.Case
  doctest ExDatalog

  test "greets the world" do
    assert ExDatalog.hello() == :world
  end
end
