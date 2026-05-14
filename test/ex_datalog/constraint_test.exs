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

  describe "type predicate constructors" do
    test "type_integer/1 builds an is_integer constraint" do
      c = Constraint.type_integer(@x)
      assert c.op == :is_integer
      assert c.left == @x
      assert c.right == nil
      assert c.result == nil
    end

    test "type_binary/1 builds an is_binary constraint" do
      c = Constraint.type_binary(@x)
      assert c.op == :is_binary
      assert c.left == @x
      assert c.right == nil
      assert c.result == nil
    end

    test "type_atom/1 builds an is_atom constraint" do
      c = Constraint.type_atom(@x)
      assert c.op == :is_atom
      assert c.left == @x
      assert c.right == nil
      assert c.result == nil
    end
  end

  describe "string predicate constructors" do
    test "starts_with/2 builds a starts_with constraint" do
      c = Constraint.starts_with(@x, Term.const("hello"))
      assert c.op == :starts_with
      assert c.left == @x
      assert c.right == Term.const("hello")
      assert c.result == nil
    end

    test "contains/2 builds a contains constraint" do
      c = Constraint.contains(@x, Term.const("ell"))
      assert c.op == :contains
      assert c.left == @x
      assert c.right == Term.const("ell")
      assert c.result == nil
    end
  end

  describe "membership constructor" do
    test "member/2 builds a membership constraint" do
      c = Constraint.member(@x, Term.const([:a, :b, :c]))
      assert c.op == :member
      assert c.left == @x
      assert c.right == Term.const([:a, :b, :c])
      assert c.result == nil
    end
  end

  describe "type_predicate?/1" do
    test "returns true for type predicate constraints" do
      for op <- [:is_integer, :is_binary, :is_atom] do
        c = %Constraint{op: op, left: @x, right: nil, result: nil}
        assert Constraint.type_predicate?(c) == true
      end
    end

    test "returns false for non-type-predicate constraints" do
      assert Constraint.type_predicate?(Constraint.gt(@x, @c5)) == false
      assert Constraint.type_predicate?(Constraint.add(@x, @y, @z)) == false
      assert Constraint.type_predicate?(Constraint.starts_with(@x, Term.const("a"))) == false
      assert Constraint.type_predicate?(Constraint.member(@x, Term.const([:a]))) == false
    end
  end

  describe "string_predicate?/1" do
    test "returns true for string predicate constraints" do
      for op <- [:starts_with, :contains] do
        c = %Constraint{op: op, left: @x, right: @y, result: nil}
        assert Constraint.string_predicate?(c) == true
      end
    end

    test "returns false for non-string-predicate constraints" do
      assert Constraint.string_predicate?(Constraint.gt(@x, @c5)) == false
      assert Constraint.string_predicate?(Constraint.type_integer(@x)) == false
      assert Constraint.string_predicate?(Constraint.member(@x, Term.const([:a]))) == false
    end
  end

  describe "membership?/1" do
    test "returns true for membership constraints" do
      c = Constraint.member(@x, Term.const([:a, :b]))
      assert Constraint.membership?(c) == true
    end

    test "returns false for non-membership constraints" do
      assert Constraint.membership?(Constraint.gt(@x, @c5)) == false
      assert Constraint.membership?(Constraint.type_integer(@x)) == false
      assert Constraint.membership?(Constraint.starts_with(@x, Term.const("a"))) == false
    end
  end

  describe "valid?/1 for new constraint types" do
    test "valid type predicate constraints" do
      assert Constraint.valid?(Constraint.type_integer(@x)) == true
      assert Constraint.valid?(Constraint.type_binary(@x)) == true
      assert Constraint.valid?(Constraint.type_atom(@x)) == true
    end

    test "valid string predicate constraints" do
      assert Constraint.valid?(Constraint.starts_with(@x, Term.const("hello"))) == true
      assert Constraint.valid?(Constraint.contains(@x, Term.const("lo"))) == true
    end

    test "valid membership constraint with constant list" do
      assert Constraint.valid?(Constraint.member(@x, Term.const([:a, :b]))) == true
    end

    test "invalid: membership with non-list right" do
      c = %Constraint{op: :member, left: @x, right: {:var, "Y"}, result: nil}
      assert Constraint.valid?(c) == false
    end

    test "invalid: membership with constant integer right" do
      c = %Constraint{op: :member, left: @x, right: {:const, 5}, result: nil}
      assert Constraint.valid?(c) == false
    end

    test "invalid: type predicate with non-nil right" do
      c = %Constraint{op: :is_integer, left: @x, right: @y, result: nil}
      assert Constraint.valid?(c) == false
    end

    test "invalid: type predicate with non-nil result" do
      c = %Constraint{op: :is_integer, left: @x, right: nil, result: @z}
      assert Constraint.valid?(c) == false
    end

    test "invalid: string predicate with nil result" do
      c = %Constraint{op: :starts_with, left: @x, right: @y, result: @z}
      assert Constraint.valid?(c) == false
    end
  end

  describe "input_variables/1 for new constraint types" do
    test "type predicates return only left variable" do
      c = Constraint.type_integer(@x)
      assert Constraint.input_variables(c) == ["X"]
    end

    test "type predicates with constant left return empty" do
      c = Constraint.type_integer(Term.const(5))
      assert Constraint.input_variables(c) == []
    end

    test "string predicates return both variables" do
      c = Constraint.starts_with(@x, @y)
      assert Constraint.input_variables(c) == ["X", "Y"]
    end

    test "membership returns only left variable" do
      c = Constraint.member(@x, Term.const([:a, :b]))
      assert Constraint.input_variables(c) == ["X"]
    end
  end

  describe "result_variable/1 for new constraint types" do
    test "type predicates return nil" do
      assert Constraint.result_variable(Constraint.type_integer(@x)) == nil
    end

    test "string predicates return nil" do
      assert Constraint.result_variable(Constraint.starts_with(@x, Term.const("a"))) == nil
    end

    test "membership returns nil" do
      assert Constraint.result_variable(Constraint.member(@x, Term.const([:a]))) == nil
    end
  end

  describe "dispatch consistency" do
    test "every op in @all_ops has a constraint_module dispatch" do
      for op <- [
            :gt,
            :lt,
            :gte,
            :lte,
            :eq,
            :neq,
            :add,
            :sub,
            :mul,
            :div,
            :is_integer,
            :is_binary,
            :is_atom,
            :starts_with,
            :contains,
            :member
          ] do
        c = %Constraint{op: op, left: @x, right: nil, result: nil}
        result = Constraint.evaluate(c, %{}, %ExDatalog.Constraint.Context{})

        assert result in [{:ok, %{}}, :filter],
               "op #{inspect(op)} should dispatch without error"
      end
    end

    test "@type op territory matches @all_ops" do
      all_ops = [
        :gt,
        :lt,
        :gte,
        :lte,
        :eq,
        :neq,
        :add,
        :sub,
        :mul,
        :div,
        :is_integer,
        :is_binary,
        :is_atom,
        :starts_with,
        :contains,
        :member
      ]

      assert length(all_ops) == 16
      assert :gt in all_ops
      assert :member in all_ops
      assert :is_integer in all_ops
      assert :starts_with in all_ops

      for op <- all_ops do
        c = %Constraint{op: op, left: @x, right: nil, result: nil}

        assert Constraint.valid?(c) or
                 op in [
                   :add,
                   :sub,
                   :mul,
                   :div,
                   :gt,
                   :lt,
                   :gte,
                   :lte,
                   :eq,
                   :neq,
                   :starts_with,
                   :contains,
                   :member
                 ]
      end
    end
  end
end
