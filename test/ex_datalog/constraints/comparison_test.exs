defmodule ExDatalog.Constraints.ComparisonTest do
  use ExUnit.Case, async: true

  alias ExDatalog.Constraint.Context
  alias ExDatalog.Constraints.Comparison
  alias ExDatalog.IR.Constraint

  describe "evaluate/3 — greater than" do
    test "passes when left > right" do
      c = %Constraint{op: :gt, left: {:var, "X"}, right: {:var, "Y"}, result: nil}

      assert {:ok, %{"X" => 10, "Y" => 3}} =
               Comparison.evaluate(c, %{"X" => 10, "Y" => 3}, %Context{})
    end

    test "filters when left <= right" do
      c = %Constraint{op: :gt, left: {:var, "X"}, right: {:var, "Y"}, result: nil}
      assert :filter = Comparison.evaluate(c, %{"X" => 3, "Y" => 10}, %Context{})
    end

    test "filters when left == right" do
      c = %Constraint{op: :gt, left: {:var, "X"}, right: {:var, "Y"}, result: nil}
      assert :filter = Comparison.evaluate(c, %{"X" => 5, "Y" => 5}, %Context{})
    end
  end

  describe "evaluate/3 — less than" do
    test "passes when left < right" do
      c = %Constraint{op: :lt, left: {:var, "X"}, right: {:const, {:int, 10}}, result: nil}
      assert {:ok, %{"X" => 5}} = Comparison.evaluate(c, %{"X" => 5}, %Context{})
    end

    test "filters when left >= right" do
      c = %Constraint{op: :lt, left: {:var, "X"}, right: {:const, {:int, 10}}, result: nil}
      assert :filter = Comparison.evaluate(c, %{"X" => 10}, %Context{})
    end
  end

  describe "evaluate/3 — greater than or equal" do
    test "passes when left >= right" do
      c = %Constraint{op: :gte, left: {:var, "X"}, right: {:const, {:int, 10}}, result: nil}
      assert {:ok, %{"X" => 10}} = Comparison.evaluate(c, %{"X" => 10}, %Context{})
    end

    test "filters when left < right" do
      c = %Constraint{op: :gte, left: {:var, "X"}, right: {:const, {:int, 10}}, result: nil}
      assert :filter = Comparison.evaluate(c, %{"X" => 9}, %Context{})
    end
  end

  describe "evaluate/3 — less than or equal" do
    test "passes when left <= right" do
      c = %Constraint{op: :lte, left: {:var, "X"}, right: {:const, {:int, 100}}, result: nil}
      assert {:ok, %{"X" => 100}} = Comparison.evaluate(c, %{"X" => 100}, %Context{})
    end

    test "filters when left > right" do
      c = %Constraint{op: :lte, left: {:var, "X"}, right: {:const, {:int, 100}}, result: nil}
      assert :filter = Comparison.evaluate(c, %{"X" => 101}, %Context{})
    end
  end

  describe "evaluate/3 — equality" do
    test "passes when left == right" do
      c = %Constraint{op: :eq, left: {:var, "X"}, right: {:const, {:atom, :alice}}, result: nil}
      assert {:ok, %{"X" => :alice}} = Comparison.evaluate(c, %{"X" => :alice}, %Context{})
    end

    test "filters when left != right" do
      c = %Constraint{op: :eq, left: {:var, "X"}, right: {:const, {:atom, :alice}}, result: nil}
      assert :filter = Comparison.evaluate(c, %{"X" => :bob}, %Context{})
    end
  end

  describe "evaluate/3 — inequality" do
    test "passes when left != right" do
      c = %Constraint{op: :neq, left: {:var, "X"}, right: {:var, "Y"}, result: nil}

      assert {:ok, %{"X" => 1, "Y" => 2}} =
               Comparison.evaluate(c, %{"X" => 1, "Y" => 2}, %Context{})
    end

    test "filters when left == right" do
      c = %Constraint{op: :neq, left: {:var, "X"}, right: {:var, "Y"}, result: nil}
      assert :filter = Comparison.evaluate(c, %{"X" => 5, "Y" => 5}, %Context{})
    end
  end

  describe "evaluate/3 — unbound variables" do
    test "filters when variable is unbound" do
      c = %Constraint{op: :gt, left: {:var, "X"}, right: {:const, {:int, 0}}, result: nil}
      assert :filter = Comparison.evaluate(c, %{}, %Context{})
    end
  end
end
