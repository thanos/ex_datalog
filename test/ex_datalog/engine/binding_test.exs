defmodule ExDatalog.Engine.BindingTest do
  use ExUnit.Case, async: true

  alias ExDatalog.Engine.Binding

  describe "empty/0" do
    test "returns an empty map" do
      assert Binding.empty() == %{}
    end
  end

  describe "bind/3" do
    test "binds a variable to a value" do
      assert Binding.bind(%{}, "X", :alice) == %{"X" => :alice}
    end

    test "binds multiple variables" do
      b = Binding.empty() |> Binding.bind("X", 1) |> Binding.bind("Y", 2)
      assert b == %{"X" => 1, "Y" => 2}
    end

    test "overwrites an existing binding" do
      b = Binding.empty() |> Binding.bind("X", 1) |> Binding.bind("X", 2)
      assert b == %{"X" => 2}
    end
  end

  describe "get/2" do
    test "returns :ok with value when bound" do
      assert Binding.get(%{"X" => :alice}, "X") == {:ok, :alice}
    end

    test "returns :error when not bound" do
      assert Binding.get(%{}, "X") == :error
    end
  end

  describe "resolve/2" do
    test "resolves a bound variable" do
      assert Binding.resolve(%{"X" => 42}, {:var, "X"}) == {:ok, 42}
    end

    test "returns :unbound for unbound variable" do
      assert Binding.resolve(%{}, {:var, "X"}) == :unbound
    end

    test "resolves an integer constant" do
      assert Binding.resolve(%{}, {:const, {:int, 10}}) == {:ok, 10}
    end

    test "resolves a string constant" do
      assert Binding.resolve(%{}, {:const, {:str, "hello"}}) == {:ok, "hello"}
    end

    test "resolves an atom constant" do
      assert Binding.resolve(%{}, {:const, {:atom, :alice}}) == {:ok, :alice}
    end

    test "returns :wildcard for wildcard" do
      assert Binding.resolve(%{}, :wildcard) == :wildcard
    end
  end

  describe "merge/2" do
    test "merges disjoint bindings" do
      assert Binding.merge(%{"X" => 1}, %{"Y" => 2}) == {:ok, %{"X" => 1, "Y" => 2}}
    end

    test "merges bindings with shared variables that agree" do
      assert Binding.merge(%{"X" => 1, "Y" => 2}, %{"X" => 1, "Z" => 3}) ==
               {:ok, %{"X" => 1, "Y" => 2, "Z" => 3}}
    end

    test "returns :conflict for shared variables that disagree" do
      assert Binding.merge(%{"X" => 1}, %{"X" => 2}) == :conflict
    end

    test "merges two empty bindings" do
      assert Binding.merge(%{}, %{}) == {:ok, %{}}
    end
  end

  describe "consistent?/2" do
    test "returns true for disjoint bindings" do
      assert Binding.consistent?(%{"X" => 1}, %{"Y" => 2})
    end

    test "returns true when shared variables agree" do
      assert Binding.consistent?(%{"X" => 1, "Y" => 2}, %{"X" => 1, "Z" => 3})
    end

    test "returns false when shared variables disagree" do
      refute Binding.consistent?(%{"X" => 1}, %{"X" => 2})
    end

    test "returns true for empty bindings" do
      assert Binding.consistent?(%{}, %{})
    end
  end

  describe "ir_value_to_native/1" do
    test "converts integer IR value" do
      assert Binding.ir_value_to_native({:int, 42}) == 42
    end

    test "converts string IR value" do
      assert Binding.ir_value_to_native({:str, "hello"}) == "hello"
    end

    test "converts atom IR value" do
      assert Binding.ir_value_to_native({:atom, :alice}) == :alice
    end
  end
end
