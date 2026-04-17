defmodule ExDatalog.ConstraintTest do
  use ExUnit.Case, async: true
  doctest ExDatalog.Constraint

  alias ExDatalog.{Constraint, Term}

  # Reusable terms
  @x Term.var("X")
  @y Term.var("Y")
  @z Term.var("Z")
  @c5 Term.const(5)

  describe "comparison constructors" do
    test "gt/2 builds a greater-than constraint" do
      c = Constraint.gt(@x, @c5)
      assert c.op == :gt
      assert c.left == @x
      assert c.right == @c5
      assert c.result == nil
    end

    test "lt/2 builds a less-than constraint" do
      c = Constraint.lt(@x, @c5)
      assert c.op == :lt
      assert c.result == nil
    end

    test "gte/2 builds a gte constraint" do
      c = Constraint.gte(@x, @c5)
      assert c.op == :gte
      assert c.result == nil
    end

    test "lte/2 builds a lte constraint" do
      c = Constraint.lte(@x, @c5)
      assert c.op == :lte
      assert c.result == nil
    end

    test "eq/2 builds an equality constraint" do
      c = Constraint.eq(@x, Term.const(:alice))
      assert c.op == :eq
      assert c.result == nil
    end

    test "neq/2 builds an inequality constraint" do
      c = Constraint.neq(@x, @y)
      assert c.op == :neq
      assert c.result == nil
    end
  end

  describe "arithmetic constructors" do
    test "add/3 builds an addition constraint with result binding" do
      c = Constraint.add(@x, @y, @z)
      assert c.op == :add
      assert c.left == @x
      assert c.right == @y
      assert c.result == @z
    end

    test "sub/3 builds a subtraction constraint" do
      c = Constraint.sub(@x, Term.const(1), @y)
      assert c.op == :sub
      assert c.result == @y
    end

    test "mul/3 builds a multiplication constraint" do
      c = Constraint.mul(@x, Term.const(2), @y)
      assert c.op == :mul
      assert c.result == @y
    end

    test "div/3 builds a division constraint" do
      c = Constraint.div(@x, Term.const(2), @y)
      assert c.op == :div
      assert c.result == @y
    end
  end

  describe "comparison?/1" do
    test "returns true for comparison constraints" do
      for op <- [:gt, :lt, :gte, :lte, :eq, :neq] do
        c = %Constraint{op: op, left: @x, right: @y, result: nil}
        assert Constraint.comparison?(c) == true
      end
    end

    test "returns false for arithmetic constraints" do
      for op <- [:add, :sub, :mul, :div] do
        c = %Constraint{op: op, left: @x, right: @y, result: @z}
        assert Constraint.comparison?(c) == false
      end
    end
  end

  describe "arithmetic?/1" do
    test "returns true for arithmetic constraints" do
      for op <- [:add, :sub, :mul, :div] do
        c = %Constraint{op: op, left: @x, right: @y, result: @z}
        assert Constraint.arithmetic?(c) == true
      end
    end

    test "returns false for comparison constraints" do
      for op <- [:gt, :lt, :gte, :lte, :eq, :neq] do
        c = %Constraint{op: op, left: @x, right: @y, result: nil}
        assert Constraint.arithmetic?(c) == false
      end
    end
  end

  describe "valid?/1" do
    test "valid comparison constraint" do
      assert Constraint.valid?(Constraint.gt(@x, @c5)) == true
    end

    test "valid arithmetic constraint" do
      assert Constraint.valid?(Constraint.add(@x, @y, @z)) == true
    end

    test "valid comparison with const terms" do
      assert Constraint.valid?(Constraint.eq(Term.const(:alice), Term.const(:bob))) == true
    end

    test "valid comparison with wildcard right" do
      assert Constraint.valid?(Constraint.gt(@x, Term.wildcard())) == true
    end

    test "invalid: bad op" do
      c = %Constraint{op: :bad, left: @x, right: @y, result: nil}
      assert Constraint.valid?(c) == false
    end

    test "invalid: arithmetic with nil result" do
      c = %Constraint{op: :add, left: @x, right: @y, result: nil}
      assert Constraint.valid?(c) == false
    end

    test "invalid: comparison with non-nil result" do
      c = %Constraint{op: :gt, left: @x, right: @y, result: @z}
      assert Constraint.valid?(c) == false
    end

    test "invalid: bad left term" do
      c = %Constraint{op: :gt, left: :bad_term, right: @y, result: nil}
      assert Constraint.valid?(c) == false
    end

    test "invalid: non-struct" do
      assert Constraint.valid?(:not_a_constraint) == false
    end
  end

  describe "input_variables/1" do
    test "returns variable names from left and right" do
      c = Constraint.gt(@x, @y)
      assert Constraint.input_variables(c) == ["X", "Y"]
    end

    test "excludes const terms" do
      c = Constraint.gt(@x, @c5)
      assert Constraint.input_variables(c) == ["X"]
    end

    test "returns empty when no variables" do
      c = Constraint.eq(Term.const(1), Term.const(2))
      assert Constraint.input_variables(c) == []
    end

    test "works for arithmetic constraints (excludes result)" do
      c = Constraint.add(@x, @y, @z)
      assert Constraint.input_variables(c) == ["X", "Y"]
    end
  end

  describe "result_variable/1" do
    test "returns variable name for arithmetic constraint" do
      c = Constraint.add(@x, @y, @z)
      assert Constraint.result_variable(c) == "Z"
    end

    test "returns nil for comparison constraint" do
      c = Constraint.gt(@x, @c5)
      assert Constraint.result_variable(c) == nil
    end
  end
end
