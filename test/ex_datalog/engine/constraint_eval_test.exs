defmodule ExDatalog.Engine.ConstraintEvalTest do
  use ExUnit.Case, async: true

  alias ExDatalog.Engine.ConstraintEval
  alias ExDatalog.IR.Constraint

  describe "comparison constraints" do
    test "gt passes when left > right" do
      c = %Constraint{op: :gt, left: {:var, "X"}, right: {:var, "Y"}, result: nil}
      assert ConstraintEval.apply([c], %{"X" => 10, "Y" => 3}) == {:ok, %{"X" => 10, "Y" => 3}}
    end

    test "gt filters when left <= right" do
      c = %Constraint{op: :gt, left: {:var, "X"}, right: {:var, "Y"}, result: nil}
      assert ConstraintEval.apply([c], %{"X" => 3, "Y" => 10}) == :filter
    end

    test "lt passes when left < right" do
      c = %Constraint{op: :lt, left: {:var, "X"}, right: {:var, "Y"}, result: nil}
      assert ConstraintEval.apply([c], %{"X" => 3, "Y" => 10}) == {:ok, %{"X" => 3, "Y" => 10}}
    end

    test "gte passes when left >= right" do
      c = %Constraint{op: :gte, left: {:var, "X"}, right: {:var, "Y"}, result: nil}
      assert ConstraintEval.apply([c], %{"X" => 10, "Y" => 10}) == {:ok, %{"X" => 10, "Y" => 10}}
    end

    test "lte filters when left > right" do
      c = %Constraint{op: :lte, left: {:var, "X"}, right: {:var, "Y"}, result: nil}
      assert ConstraintEval.apply([c], %{"X" => 10, "Y" => 3}) == :filter
    end

    test "eq passes when left == right" do
      c = %Constraint{op: :eq, left: {:var, "X"}, right: {:var, "Y"}, result: nil}
      assert ConstraintEval.apply([c], %{"X" => 5, "Y" => 5}) == {:ok, %{"X" => 5, "Y" => 5}}
    end

    test "neq passes when left != right" do
      c = %Constraint{op: :neq, left: {:var, "X"}, right: {:var, "Y"}, result: nil}
      assert ConstraintEval.apply([c], %{"X" => 5, "Y" => 3}) == {:ok, %{"X" => 5, "Y" => 3}}
    end

    test "comparison with constant" do
      c = %Constraint{op: :gt, left: {:var, "X"}, right: {:const, {:int, 0}}, result: nil}
      assert ConstraintEval.apply([c], %{"X" => 10}) == {:ok, %{"X" => 10}}
      assert ConstraintEval.apply([c], %{"X" => -1}) == :filter
    end

    test "unbound variable filters" do
      c = %Constraint{op: :gt, left: {:var, "X"}, right: {:var, "Y"}, result: nil}
      assert ConstraintEval.apply([c], %{"X" => 10}) == :filter
    end
  end

  describe "arithmetic constraints" do
    test "add binds result variable" do
      c = %Constraint{op: :add, left: {:var, "X"}, right: {:var, "Y"}, result: {:var, "Z"}}

      assert ConstraintEval.apply([c], %{"X" => 3, "Y" => 7}) ==
               {:ok, %{"X" => 3, "Y" => 7, "Z" => 10}}
    end

    test "sub binds result variable" do
      c = %Constraint{op: :sub, left: {:var, "X"}, right: {:var, "Y"}, result: {:var, "Z"}}

      assert ConstraintEval.apply([c], %{"X" => 10, "Y" => 3}) ==
               {:ok, %{"X" => 10, "Y" => 3, "Z" => 7}}
    end

    test "mul binds result variable" do
      c = %Constraint{op: :mul, left: {:var, "X"}, right: {:var, "Y"}, result: {:var, "Z"}}

      assert ConstraintEval.apply([c], %{"X" => 3, "Y" => 4}) ==
               {:ok, %{"X" => 3, "Y" => 4, "Z" => 12}}
    end

    test "div binds result variable with integer division" do
      c = %Constraint{op: :div, left: {:var, "X"}, right: {:var, "Y"}, result: {:var, "Z"}}

      assert ConstraintEval.apply([c], %{"X" => 10, "Y" => 3}) ==
               {:ok, %{"X" => 10, "Y" => 3, "Z" => 3}}
    end

    test "division by zero filters" do
      c = %Constraint{
        op: :div,
        left: {:var, "X"},
        right: {:const, {:int, 0}},
        result: {:var, "Z"}
      }

      assert ConstraintEval.apply([c], %{"X" => 10}) == :filter
    end

    test "arithmetic with constant operand" do
      c = %Constraint{
        op: :add,
        left: {:var, "X"},
        right: {:const, {:int, 1}},
        result: {:var, "Y"}
      }

      assert ConstraintEval.apply([c], %{"X" => 5}) == {:ok, %{"X" => 5, "Y" => 6}}
    end
  end

  describe "mixed constraints" do
    test "comparison followed by arithmetic" do
      c1 = %Constraint{op: :gt, left: {:var, "X"}, right: {:const, {:int, 0}}, result: nil}
      c2 = %Constraint{op: :add, left: {:var, "X"}, right: {:var, "Y"}, result: {:var, "Z"}}

      assert ConstraintEval.apply([c1, c2], %{"X" => 5, "Y" => 3}) ==
               {:ok, %{"X" => 5, "Y" => 3, "Z" => 8}}
    end

    test "arithmetic result used in subsequent comparison" do
      c1 = %Constraint{
        op: :add,
        left: {:var, "X"},
        right: {:const, {:int, 1}},
        result: {:var, "Y"}
      }

      c2 = %Constraint{op: :lt, left: {:var, "Y"}, right: {:const, {:int, 10}}, result: nil}

      assert ConstraintEval.apply([c1, c2], %{"X" => 5}) ==
               {:ok, %{"X" => 5, "Y" => 6}}

      assert ConstraintEval.apply([c1, c2], %{"X" => 20}) == :filter
    end

    test "empty constraint list returns binding unchanged" do
      binding = %{"X" => 1}
      assert ConstraintEval.apply([], binding) == {:ok, binding}
    end

    test "first comparison fail short-circuits" do
      c1 = %Constraint{op: :gt, left: {:var, "X"}, right: {:const, {:int, 100}}, result: nil}

      c2 = %Constraint{
        op: :add,
        left: {:var, "X"},
        right: {:const, {:int, 1}},
        result: {:var, "Y"}
      }

      assert ConstraintEval.apply([c1, c2], %{"X" => 5}) == :filter
    end
  end

  describe "apply_one/2" do
    test "applies a single comparison constraint" do
      c = %Constraint{op: :eq, left: {:var, "X"}, right: {:const, {:atom, :alice}}, result: nil}
      assert ConstraintEval.apply_one(c, %{"X" => :alice}) == {:ok, %{"X" => :alice}}
    end

    test "filters on unbound variable" do
      c = %Constraint{op: :gt, left: {:var, "X"}, right: {:var, "Y"}, result: nil}
      assert ConstraintEval.apply_one(c, %{"X" => 10}) == :filter
    end
  end
end
