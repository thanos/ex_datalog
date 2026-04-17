defmodule ExDatalog.IRTest do
  use ExUnit.Case, async: true
  doctest ExDatalog.IR

  alias ExDatalog.IR

  describe "from_term/1" do
    test "converts var term" do
      assert IR.from_term({:var, "X"}) == {:var, "X"}
    end

    test "converts integer const term" do
      assert IR.from_term({:const, 42}) == {:const, {:int, 42}}
    end

    test "converts atom const term" do
      assert IR.from_term({:const, :alice}) == {:const, {:atom, :alice}}
    end

    test "converts string const term" do
      assert IR.from_term({:const, "hello"}) == {:const, {:str, "hello"}}
    end

    test "converts wildcard" do
      assert IR.from_term(:wildcard) == :wildcard
    end
  end

  describe "from_atom/1" do
    test "converts an AST atom to an IR atom" do
      ast_atom = ExDatalog.Atom.new("parent", [{:var, "X"}, {:const, :alice}])
      ir_atom = IR.from_atom(ast_atom)

      assert %IR.Atom{relation: "parent", terms: terms} = ir_atom
      assert terms == [{:var, "X"}, {:const, {:atom, :alice}}]
    end
  end

  describe "from_constraint/1" do
    test "converts comparison constraint" do
      ast_c = ExDatalog.Constraint.gt({:var, "X"}, {:const, 0})
      ir_c = IR.from_constraint(ast_c)

      assert %IR.Constraint{op: :gt, left: {:var, "X"}, right: {:const, {:int, 0}}, result: nil} =
               ir_c
    end

    test "converts arithmetic constraint" do
      ast_c = ExDatalog.Constraint.add({:var, "A"}, {:var, "B"}, {:var, "Z"})
      ir_c = IR.from_constraint(ast_c)

      assert %IR.Constraint{op: :add, left: {:var, "A"}, right: {:var, "B"}, result: {:var, "Z"}} =
               ir_c
    end
  end

  describe "serialize/1" do
    test "IR.Relation.serialize/1 produces a plain map" do
      rel = %IR.Relation{name: "parent", arity: 2, types: [:atom, :atom]}
      serialized = IR.Relation.serialize(rel)

      assert serialized == %{name: "parent", arity: 2, types: [:atom, :atom]}
    end

    test "IR.Fact.serialize/1 produces a plain map" do
      fact = %IR.Fact{relation: "parent", values: [{:atom, :alice}, {:atom, :bob}]}
      serialized = IR.Fact.serialize(fact)

      assert serialized == %{relation: "parent", values: [{:atom, :alice}, {:atom, :bob}]}
    end

    test "IR.Atom.serialize/1 produces a plain map" do
      atom = %IR.Atom{relation: "parent", terms: [{:var, "X"}, {:const, {:atom, :alice}}]}
      serialized = IR.Atom.serialize(atom)

      assert serialized == %{relation: "parent", terms: [{:var, "X"}, {:const, {:atom, :alice}}]}
    end

    test "IR.Constraint.serialize/1 omits result key when nil" do
      c = %IR.Constraint{op: :gt, left: {:var, "X"}, right: {:const, {:int, 0}}, result: nil}
      serialized = IR.Constraint.serialize(c)

      assert Map.has_key?(serialized, :result) == false
      assert serialized.op == :gt
    end

    test "IR.Constraint.serialize/1 includes result key when present" do
      c = %IR.Constraint{op: :add, left: {:var, "A"}, right: {:var, "B"}, result: {:var, "Z"}}
      serialized = IR.Constraint.serialize(c)

      assert serialized.result == {:var, "Z"}
    end

    test "IR.serialize/1 produces a complete plain map" do
      ir = %IR{
        relations: [%IR.Relation{name: "edge", arity: 2, types: [:atom, :atom]}],
        facts: [%IR.Fact{relation: "edge", values: [{:atom, :a}, {:atom, :b}]}],
        rules: [],
        strata: [%IR.Stratum{index: 0, rule_ids: [], relations: []}],
        metadata: %{}
      }

      serialized = IR.serialize(ir)

      assert is_map(serialized)
      assert is_list(serialized.relations)
      assert is_list(serialized.facts)
      assert is_list(serialized.rules)
      assert is_list(serialized.strata)
    end
  end
end
