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
    test "every category op dispatches without error" do
      comparison_ops = [:gt, :lt, :gte, :lte, :eq, :neq]
      arithmetic_ops = [:add, :sub, :mul, :div]
      type_ops = [:is_integer, :is_binary, :is_atom]
      string_ops = [:starts_with, :contains]
      membership_ops = [:member]

      for op <- comparison_ops ++ arithmetic_ops ++ type_ops ++ string_ops ++ membership_ops do
        c = %Constraint{op: op, left: @x, right: nil, result: nil}
        result = Constraint.evaluate(c, %{}, %ExDatalog.Constraint.Context{})

        assert result in [{:ok, %{}}, :filter],
               "op #{inspect(op)} should dispatch without error"
      end
    end

    test "constraint_module/1 dispatches every category to the right module" do
      modules = [
        {ExDatalog.Constraints.Comparison, [:gt, :lt, :gte, :lte, :eq, :neq]},
        {ExDatalog.Constraints.Arithmetic, [:add, :sub, :mul, :div]},
        {ExDatalog.Constraints.Type, [:is_integer, :is_binary, :is_atom]},
        {ExDatalog.Constraints.StringPredicate, [:starts_with, :contains]},
        {ExDatalog.Constraints.Membership, [:member]}
      ]

      for {_module, ops} <- modules do
        all_ops = Enum.flat_map(modules, fn {_mod, ops} -> ops end)
        assert length(all_ops) == 16

        for op <- ops do
          ir = %ExDatalog.IR.Constraint{
            op: op,
            left: {:var, "X"},
            right: {:var, "Y"},
            result: nil
          }

          result = Constraint.evaluate(ir, %{}, %ExDatalog.Constraint.Context{})

          assert result in [{:ok, %{}}, :filter, {:ok, %{"X" => 10}}],
                 "op #{inspect(op)} should dispatch through Constraint.evaluate/3"
        end
      end
    end

    test "valid?/1 returns true for all ops in @all_ops" do
      valid_constraints = [
        Constraint.gt(@x, @y),
        Constraint.lt(@x, @y),
        Constraint.gte(@x, @y),
        Constraint.lte(@x, @y),
        Constraint.eq(@x, @y),
        Constraint.neq(@x, @y),
        Constraint.add(@x, @y, @z),
        Constraint.sub(@x, @y, @z),
        Constraint.mul(@x, @y, @z),
        Constraint.div(@x, @y, @z),
        Constraint.type_integer(@x),
        Constraint.type_binary(@x),
        Constraint.type_atom(@x),
        Constraint.starts_with(@x, Term.const("hello")),
        Constraint.contains(@x, Term.const("ell")),
        Constraint.member(@x, Term.const([:a, :b]))
      ]

      for c <- valid_constraints do
        assert Constraint.valid?(c), "op #{inspect(c.op)} should be valid"
      end
    end
  end

  describe "evaluate/3 — public struct dispatch" do
    test "dispatches through public Constraint struct" do
      c = Constraint.gt(@x, @y)

      assert {:ok, %{"X" => 10, "Y" => 3}} =
               Constraint.evaluate(c, %{"X" => 10, "Y" => 3}, %ExDatalog.Constraint.Context{})
    end

    test "dispatches comparison through public struct" do
      c = Constraint.lt(@x, @c5)

      assert {:ok, %{"X" => 3}} =
               Constraint.evaluate(c, %{"X" => 3}, %ExDatalog.Constraint.Context{})

      assert :filter = Constraint.evaluate(c, %{"X" => 10}, %ExDatalog.Constraint.Context{})
    end

    test "dispatches arithmetic through public struct" do
      c = Constraint.add(@x, @y, @z)

      assert {:ok, %{"X" => 3, "Y" => 7, "Z" => 10}} =
               Constraint.evaluate(c, %{"X" => 3, "Y" => 7}, %ExDatalog.Constraint.Context{})
    end

    test "dispatches type predicate through public struct" do
      c = Constraint.type_integer(@x)

      assert {:ok, %{"X" => 42}} =
               Constraint.evaluate(c, %{"X" => 42}, %ExDatalog.Constraint.Context{})

      assert :filter = Constraint.evaluate(c, %{"X" => :atom}, %ExDatalog.Constraint.Context{})
    end

test "dispatches membership through public struct" do
      c = Constraint.member(@x, Term.const([:a, :b, :c]))

      assert {:ok, %{"X" => :a}} =
                Constraint.evaluate(c, %{"X" => :a}, %ExDatalog.Constraint.Context{})

      assert :filter = Constraint.evaluate(c, %{"X" => :z}, %ExDatalog.Constraint.Context{})
    end
  end

  describe "from_tuple/1" do
    test "creates comparison constraint from shorthand" do
      c = Constraint.from_tuple({:neq, :A, :B})
      assert c == Constraint.neq(Term.var("A"), Term.var("B"))
    end

    test "creates gt constraint from shorthand with constant" do
      c = Constraint.from_tuple({:gt, :S, 100_000})
      assert c == Constraint.gt(Term.var("S"), Term.const(100_000))
    end

    test "creates arithmetic constraint from shorthand" do
      c = Constraint.from_tuple({:add, :X, :Y, :Z})
      assert c == Constraint.add(Term.var("X"), Term.var("Y"), Term.var("Z"))
    end

    test "creates sub constraint from shorthand" do
      c = Constraint.from_tuple({:sub, :X, :C, :Y})
      assert c == Constraint.sub(Term.var("X"), Term.var("C"), Term.var("Y"))
    end

    test "creates type predicate from shorthand" do
      c = Constraint.from_tuple({:is_integer, :V})
      assert c == Constraint.type_integer(Term.var("V"))
    end

    test "creates string predicate from shorthand" do
      c = Constraint.from_tuple({:starts_with, :E, "admin."})
      assert c == Constraint.starts_with(Term.var("E"), Term.const("admin."))
    end

    test "creates membership constraint from shorthand" do
      c = Constraint.from_tuple({:member, :Dept, [:engineering, :infra]})
      assert c == Constraint.member(Term.var("Dept"), Term.const([:engineering, :infra]))
    end

    test "passes through existing Constraint struct" do
      original = Constraint.neq(@x, @y)
      assert Constraint.from_tuple(original) == original
    end

    test "creates all comparison ops from shorthand" do
      for op <- [:gt, :lt, :gte, :lte, :eq, :neq] do
        c = Constraint.from_tuple({op, :A, :B})
        assert c.op == op
        assert c.left == {:var, "A"}
        assert c.right == {:var, "B"}
        assert c.result == nil
      end
    end

    test "creates all arithmetic ops from shorthand" do
      for op <- [:add, :sub, :mul, :div] do
        c = Constraint.from_tuple({op, :X, :Y, :Z})
        assert c.op == op
        assert c.left == {:var, "X"}
        assert c.right == {:var, "Y"}
        assert c.result == {:var, "Z"}
      end
    end

    test "creates all type predicate ops from shorthand" do
      for op <- [:is_integer, :is_binary, :is_atom] do
        c = Constraint.from_tuple({op, :V})
        assert c.op == op
        assert c.left == {:var, "V"}
        assert c.right == nil
        assert c.result == nil
      end
    end
  end
end
