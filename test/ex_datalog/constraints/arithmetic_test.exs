defmodule ExDatalog.Constraints.ArithmeticTest do
  use ExUnit.Case, async: true

  alias ExDatalog.Constraint.Context
  alias ExDatalog.Constraints.Arithmetic
  alias ExDatalog.IR.Constraint

  describe "evaluate/3 — addition" do
    test "adds two bound variables and binds result" do
      c = %Constraint{op: :add, left: {:var, "X"}, right: {:var, "Y"}, result: {:var, "Z"}}

      assert {:ok, %{"X" => 3, "Y" => 7, "Z" => 10}} =
               Arithmetic.evaluate(c, %{"X" => 3, "Y" => 7}, %Context{})
    end

    test "adds a variable and a constant" do
      c = %Constraint{
        op: :add,
        left: {:var, "X"},
        right: {:const, {:int, 5}},
        result: {:var, "Z"}
      }

      assert {:ok, %{"X" => 10, "Z" => 15}} = Arithmetic.evaluate(c, %{"X" => 10}, %Context{})
    end

    test "filters when left variable is unbound" do
      c = %Constraint{op: :add, left: {:var, "X"}, right: {:var, "Y"}, result: {:var, "Z"}}
      assert :filter = Arithmetic.evaluate(c, %{"Y" => 7}, %Context{})
    end

    test "filters when right variable is unbound" do
      c = %Constraint{op: :add, left: {:var, "X"}, right: {:var, "Y"}, result: {:var, "Z"}}
      assert :filter = Arithmetic.evaluate(c, %{"X" => 3}, %Context{})
    end
  end

  describe "evaluate/3 — subtraction" do
    test "subtracts two bound variables" do
      c = %Constraint{op: :sub, left: {:var, "X"}, right: {:var, "Y"}, result: {:var, "Z"}}

      assert {:ok, %{"X" => 10, "Y" => 3, "Z" => 7}} =
               Arithmetic.evaluate(c, %{"X" => 10, "Y" => 3}, %Context{})
    end
  end

  describe "evaluate/3 — multiplication" do
    test "multiplies two bound variables" do
      c = %Constraint{op: :mul, left: {:var, "X"}, right: {:var, "Y"}, result: {:var, "Z"}}

      assert {:ok, %{"X" => 3, "Y" => 7, "Z" => 21}} =
               Arithmetic.evaluate(c, %{"X" => 3, "Y" => 7}, %Context{})
    end
  end

  describe "evaluate/3 — division" do
    test "divides two bound variables (integer division)" do
      c = %Constraint{op: :div, left: {:var, "X"}, right: {:var, "Y"}, result: {:var, "Z"}}

      assert {:ok, %{"X" => 10, "Y" => 3, "Z" => 3}} =
               Arithmetic.evaluate(c, %{"X" => 10, "Y" => 3}, %Context{})
    end

    test "filters on division by zero" do
      c = %Constraint{op: :div, left: {:var, "X"}, right: {:var, "Y"}, result: {:var, "Z"}}
      assert :filter = Arithmetic.evaluate(c, %{"X" => 10, "Y" => 0}, %Context{})
    end
  end

  describe "evaluate/3 — wildcard filtering" do
    test "filters when operand is wildcard" do
      c = %Constraint{op: :add, left: :wildcard, right: {:var, "Y"}, result: {:var, "Z"}}
      assert :filter = Arithmetic.evaluate(c, %{"Y" => 5}, %Context{})
    end
  end
end
