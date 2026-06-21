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

  describe "from_term/1 list values" do
    test "converts const list with mixed types" do
      assert IR.from_term({:const, [1, :a, "hello"]}) ==
               {:const, {:list, [{:int, 1}, {:atom, :a}, {:str, "hello"}]}}
    end

    test "converts const single-element list" do
      assert IR.from_term({:const, [:x]}) == {:const, {:list, [{:atom, :x}]}}
    end

    test "converts const empty list" do
      assert IR.from_term({:const, []}) == {:const, {:list, []}}
    end
  end

  describe "from_constraint/1 type predicates" do
    test "converts is_integer type predicate" do
      ast_c = ExDatalog.Constraint.type_integer({:var, "X"})
      ir_c = IR.from_constraint(ast_c)
      assert %IR.Constraint{op: :is_integer, left: {:var, "X"}, right: nil, result: nil} = ir_c
    end

    test "converts is_binary type predicate" do
      ast_c = ExDatalog.Constraint.type_binary({:var, "S"})
      ir_c = IR.from_constraint(ast_c)
      assert %IR.Constraint{op: :is_binary, left: {:var, "S"}, right: nil, result: nil} = ir_c
    end

    test "converts is_atom type predicate" do
      ast_c = ExDatalog.Constraint.type_atom({:var, "X"})
      ir_c = IR.from_constraint(ast_c)
      assert %IR.Constraint{op: :is_atom, left: {:var, "X"}, right: nil, result: nil} = ir_c
    end
  end

  describe "from_constraint/1 string predicates" do
    test "converts starts_with constraint" do
      ast_c = ExDatalog.Constraint.starts_with({:var, "X"}, {:const, "hello"})
      ir_c = IR.from_constraint(ast_c)

      assert %IR.Constraint{op: :starts_with, left: {:var, "X"}, right: {:const, {:str, "hello"}}} =
               ir_c
    end

    test "converts contains constraint" do
      ast_c = ExDatalog.Constraint.contains({:var, "X"}, {:const, "ell"})
      ir_c = IR.from_constraint(ast_c)

      assert %IR.Constraint{op: :contains, left: {:var, "X"}, right: {:const, {:str, "ell"}}} =
               ir_c
    end
  end

  describe "from_constraint/1 membership" do
    test "converts member constraint" do
      ast_c = ExDatalog.Constraint.member({:var, "X"}, {:const, [:a, :b]})
      ir_c = IR.from_constraint(ast_c)

      assert %IR.Constraint{
               op: :member,
               left: {:var, "X"},
               right: {:const, {:list, [{:atom, :a}, {:atom, :b}]}}
             } = ir_c
    end
  end

  describe "resolve_operand/2" do
    test "resolves bound variable" do
      assert IR.resolve_operand({:var, "X"}, %{"X" => 42}) == {:ok, 42}
    end

    test "returns :unbound for unbound variable" do
      assert IR.resolve_operand({:var, "X"}, %{}) == :unbound
    end

    test "resolves const integer" do
      assert IR.resolve_operand({:const, {:int, 42}}, %{}) == {:ok, 42}
    end

    test "resolves const atom" do
      assert IR.resolve_operand({:const, {:atom, :foo}}, %{}) == {:ok, :foo}
    end

    test "resolves const string" do
      assert IR.resolve_operand({:const, {:str, "hello"}}, %{}) == {:ok, "hello"}
    end

    test "resolves const list" do
      assert IR.resolve_operand({:const, {:list, [{:int, 1}, {:atom, :a}]}}, %{}) ==
               {:ok, [1, :a]}
    end

    test "returns :unbound for wildcard" do
      assert IR.resolve_operand(:wildcard, %{}) == :unbound
    end
  end

  describe "value_to_native/1" do
    test "converts int" do
      assert IR.value_to_native({:int, 42}) == 42
    end

    test "converts str" do
      assert IR.value_to_native({:str, "hello"}) == "hello"
    end

    test "converts atom" do
      assert IR.value_to_native({:atom, :foo}) == :foo
    end

    test "converts list recursively" do
      assert IR.value_to_native({:list, [{:int, 1}, {:atom, :foo}, {:str, "bar"}]}) == [
               1,
               :foo,
               "bar"
             ]
    end
  end

  describe "IR.Rule.serialize/1 with constraints" do
    test "serializes rule with constraint in body" do
      rule = %IR.Rule{
        id: 0,
        head: %IR.Atom{relation: "high", terms: [{:var, "X"}]},
        body: [
          {:positive, %IR.Atom{relation: "income", terms: [{:var, "X"}, {:var, "S"}]}},
          {:constraint,
           %IR.Constraint{op: :gt, left: {:var, "S"}, right: {:const, {:int, 100}}, result: nil}}
        ],
        stratum: 0,
        metadata: %{}
      }

      serialized = IR.Rule.serialize(rule)
      assert serialized.id == 0
      assert serialized.stratum == 0
      assert length(serialized.body) == 2

      constraint_body = Enum.find(serialized.body, fn b -> b.kind == :constraint end)
      assert constraint_body.kind == :constraint
      assert constraint_body.constraint.op == :gt
    end
  end

  describe "IR.Stratum.serialize/1" do
    test "serializes stratum" do
      stratum = %IR.Stratum{index: 1, rule_ids: [0, 1], relations: ["a", "b"]}
      serialized = IR.Stratum.serialize(stratum)
      assert serialized == %{index: 1, rule_ids: [0, 1], relations: ["a", "b"]}
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

    test "IR.Constraint.serialize/1 includes result key when nil" do
      c = %IR.Constraint{op: :gt, left: {:var, "X"}, right: {:const, {:int, 0}}, result: nil}
      serialized = IR.Constraint.serialize(c)

      assert Map.has_key?(serialized, :result)
      assert serialized.result == nil
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
