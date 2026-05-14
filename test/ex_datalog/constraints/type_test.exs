defmodule ExDatalog.Constraints.TypeTest do
  use ExUnit.Case, async: true

  alias ExDatalog.Constraint.Context
  alias ExDatalog.Constraints.Type
  alias ExDatalog.IR.Constraint

  describe "evaluate/3 — is_integer" do
    test "passes when value is an integer" do
      c = %Constraint{op: :is_integer, left: {:var, "X"}, right: nil, result: nil}
      assert {:ok, %{"X" => 42}} = Type.evaluate(c, %{"X" => 42}, %Context{})
    end

    test "filters when value is a string" do
      c = %Constraint{op: :is_integer, left: {:var, "X"}, right: nil, result: nil}
      assert :filter = Type.evaluate(c, %{"X" => "hello"}, %Context{})
    end

    test "filters when value is an atom" do
      c = %Constraint{op: :is_integer, left: {:var, "X"}, right: nil, result: nil}
      assert :filter = Type.evaluate(c, %{"X" => :foo}, %Context{})
    end

    test "filters when variable is unbound" do
      c = %Constraint{op: :is_integer, left: {:var, "X"}, right: nil, result: nil}
      assert :filter = Type.evaluate(c, %{}, %Context{})
    end

    test "passes with a constant integer" do
      c = %Constraint{op: :is_integer, left: {:const, {:int, 7}}, right: nil, result: nil}
      assert {:ok, %{}} = Type.evaluate(c, %{}, %Context{})
    end
  end

  describe "evaluate/3 — is_binary" do
    test "passes when value is a string" do
      c = %Constraint{op: :is_binary, left: {:var, "X"}, right: nil, result: nil}
      assert {:ok, %{"X" => "hello"}} = Type.evaluate(c, %{"X" => "hello"}, %Context{})
    end

    test "filters when value is an integer" do
      c = %Constraint{op: :is_binary, left: {:var, "X"}, right: nil, result: nil}
      assert :filter = Type.evaluate(c, %{"X" => 42}, %Context{})
    end

    test "filters when value is an atom" do
      c = %Constraint{op: :is_binary, left: {:var, "X"}, right: nil, result: nil}
      assert :filter = Type.evaluate(c, %{"X" => :foo}, %Context{})
    end

    test "filters when variable is unbound" do
      c = %Constraint{op: :is_binary, left: {:var, "X"}, right: nil, result: nil}
      assert :filter = Type.evaluate(c, %{}, %Context{})
    end
  end

  describe "evaluate/3 — is_atom" do
    test "passes when value is an atom" do
      c = %Constraint{op: :is_atom, left: {:var, "X"}, right: nil, result: nil}
      assert {:ok, %{"X" => :foo}} = Type.evaluate(c, %{"X" => :foo}, %Context{})
    end

    test "filters when value is an integer" do
      c = %Constraint{op: :is_atom, left: {:var, "X"}, right: nil, result: nil}
      assert :filter = Type.evaluate(c, %{"X" => 42}, %Context{})
    end

    test "filters when value is a string" do
      c = %Constraint{op: :is_atom, left: {:var, "X"}, right: nil, result: nil}
      assert :filter = Type.evaluate(c, %{"X" => "hello"}, %Context{})
    end

    test "filters when variable is unbound" do
      c = %Constraint{op: :is_atom, left: {:var, "X"}, right: nil, result: nil}
      assert :filter = Type.evaluate(c, %{}, %Context{})
    end
  end

  describe "evaluate/3 — wildcard" do
    test "filters when operand is wildcard" do
      c = %Constraint{op: :is_integer, left: :wildcard, right: nil, result: nil}
      assert :filter = Type.evaluate(c, %{}, %Context{})
    end
  end
end
