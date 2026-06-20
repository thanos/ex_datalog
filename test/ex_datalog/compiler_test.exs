defmodule ExDatalog.CompilerTest do
  use ExUnit.Case, async: true

  alias ExDatalog.{Atom, Compiler, Constraint, IR, Program, Rule, Term}

  describe "compile/1 with positive rules" do
    test "compiles a simple single-rule program" do
      program =
        Program.new()
        |> Program.add_relation("edge", [:atom, :atom])
        |> Program.add_relation("path", [:atom, :atom])
        |> Program.add_rule(
          Rule.new(
            Atom.new("path", [Term.var("X"), Term.var("Y")]),
            [{:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}]
          )
        )

      assert {:ok, ir} = Compiler.compile(program)
      assert [%IR.Relation{}, %IR.Relation{}] = ir.relations
      assert [%IR.Rule{}] = ir.rules
      assert ir.facts == []
    end

    test "compiles a program with facts" do
      program =
        Program.new()
        |> Program.add_relation("edge", [:atom, :atom])
        |> Program.add_fact("edge", [:a, :b])
        |> Program.add_fact("edge", [:b, :c])

      assert {:ok, ir} = Compiler.compile(program)
      assert [%IR.Fact{}, %IR.Fact{}] = ir.facts
      assert ir.facts |> Enum.map(& &1.relation) |> Enum.all?(&(&1 == "edge"))
    end

    test "compiles a program with recursive rules" do
      program =
        Program.new()
        |> Program.add_relation("edge", [:atom, :atom])
        |> Program.add_relation("path", [:atom, :atom])
        |> Program.add_rule(
          Rule.new(
            Atom.new("path", [Term.var("X"), Term.var("Y")]),
            [{:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}]
          )
        )
        |> Program.add_rule(
          Rule.new(
            Atom.new("path", [Term.var("X"), Term.var("Z")]),
            [
              {:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])},
              {:positive, Atom.new("path", [Term.var("Y"), Term.var("Z")])}
            ]
          )
        )

      assert {:ok, ir} = Compiler.compile(program)
      assert [%IR.Rule{}, %IR.Rule{}] = ir.rules
      assert [%IR.Stratum{}] = ir.strata
      assert hd(ir.strata).index == 0
    end
  end

  describe "compile/1 with stratified negation" do
    test "compiles a program with negation across strata" do
      program =
        Program.new()
        |> Program.add_relation("male", [:atom])
        |> Program.add_relation("married", [:atom, :atom])
        |> Program.add_relation("bachelor", [:atom])
        |> Program.add_rule(
          Rule.new(
            Atom.new("bachelor", [Term.var("X")]),
            [
              {:positive, Atom.new("male", [Term.var("X")])},
              {:negative, Atom.new("married", [Term.var("X"), Term.wildcard()])}
            ]
          )
        )

      assert {:ok, ir} = Compiler.compile(program)
      assert [%IR.Rule{}] = ir.rules
      assert ir.strata != []
    end

    test "assigns higher stratum to negated relation" do
      program =
        Program.new()
        |> Program.add_relation("male", [:atom])
        |> Program.add_relation("married", [:atom, :atom])
        |> Program.add_relation("bachelor", [:atom])
        |> Program.add_rule(
          Rule.new(
            Atom.new("bachelor", [Term.var("X")]),
            [
              {:positive, Atom.new("male", [Term.var("X")])},
              {:negative, Atom.new("married", [Term.var("X"), Term.wildcard()])}
            ]
          )
        )

      assert {:ok, ir} = Compiler.compile(program)

      bachelor_rule = Enum.find(ir.rules, fn r -> r.head.relation == "bachelor" end)
      assert bachelor_rule.stratum >= 1
    end
  end

  describe "compile/1 with arithmetic constraints" do
    test "compiles a rule with an arithmetic constraint" do
      program =
        Program.new()
        |> Program.add_relation("income", [:atom, :integer])
        |> Program.add_relation("rate", [:integer])
        |> Program.add_relation("tax", [:atom, :integer])
        |> Program.add_rule(
          Rule.new(
            Atom.new("tax", [Term.var("X"), Term.var("Z")]),
            [
              {:positive, Atom.new("income", [Term.var("X"), Term.var("A")])},
              {:positive, Atom.new("rate", [Term.var("R")])}
            ],
            [Constraint.mul(Term.var("A"), Term.var("R"), Term.var("Z"))]
          )
        )

      assert {:ok, ir} = Compiler.compile(program)
      assert [%IR.Rule{}] = ir.rules

      rule = hd(ir.rules)

      constraint_literals =
        Enum.filter(rule.body, fn
          {:constraint, _} -> true
          _ -> false
        end)

      assert length(constraint_literals) == 1

      {:constraint, ir_c} = hd(constraint_literals)
      assert ir_c.op == :mul
      assert ir_c.result == {:var, "Z"}
    end
  end

  describe "compile/1 deterministic output" do
    test "same program produces identical IR across compilations" do
      program =
        Program.new()
        |> Program.add_relation("edge", [:atom, :atom])
        |> Program.add_relation("path", [:atom, :atom])
        |> Program.add_fact("edge", [:a, :b])
        |> Program.add_rule(
          Rule.new(
            Atom.new("path", [Term.var("X"), Term.var("Y")]),
            [{:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}]
          )
        )

      {:ok, ir1} = Compiler.compile(program)
      {:ok, ir2} = Compiler.compile(program)

      assert IR.serialize(ir1) == IR.serialize(ir2)
    end
  end

  describe "compile/1 rejection" do
    test "rejects an invalid program" do
      program =
        Program.new()
        |> Program.add_relation("r", [:atom])
        |> then(&%{&1 | rules: [Rule.new(Atom.new("r", [Term.var("Z")]), [])]})

      assert {:error, _errors} = Compiler.compile(program)
    end
  end

  describe "compile/1 with constraint types" do
    test "compiles a rule with comparison constraint" do
      program =
        Program.new()
        |> Program.add_relation("income", [:atom, :integer])
        |> Program.add_relation("high", [:atom, :integer])
        |> Program.add_rule(
          Rule.new(
            Atom.new("high", [Term.var("N"), Term.var("V")]),
            [{:positive, Atom.new("income", [Term.var("N"), Term.var("V")])}],
            [Constraint.gt(Term.var("V"), Term.const(100))]
          )
        )

      assert {:ok, ir} = Compiler.compile(program)
      rule = hd(ir.rules)
      constraints = for {:constraint, c} <- rule.body, do: c
      assert length(constraints) == 1
      assert hd(constraints).op == :gt
    end

    test "compiles a rule with type predicate constraint" do
      program =
        Program.new()
        |> Program.add_relation("value", [:atom, :any])
        |> Program.add_relation("int_value", [:atom, :any])
        |> Program.add_rule(
          Rule.new(
            Atom.new("int_value", [Term.var("N"), Term.var("V")]),
            [{:positive, Atom.new("value", [Term.var("N"), Term.var("V")])}],
            [Constraint.type_integer(Term.var("V"))]
          )
        )

      assert {:ok, ir} = Compiler.compile(program)
      rule = hd(ir.rules)
      constraints = for {:constraint, c} <- rule.body, do: c
      assert length(constraints) == 1
      assert hd(constraints).op == :is_integer
      assert hd(constraints).right == nil
    end

    test "compiles a rule with neq constraint" do
      program =
        Program.new()
        |> Program.add_relation("edge", [:atom, :atom])
        |> Program.add_relation("different", [:atom, :atom])
        |> Program.add_rule(
          Rule.new(
            Atom.new("different", [Term.var("X"), Term.var("Y")]),
            [{:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}],
            [Constraint.neq(Term.var("X"), Term.var("Y"))]
          )
        )

      assert {:ok, ir} = Compiler.compile(program)
      rule = hd(ir.rules)
      constraints = for {:constraint, c} <- rule.body, do: c
      assert length(constraints) == 1
      assert hd(constraints).op == :neq
    end

    test "compiles a rule with string predicate constraint" do
      program =
        Program.new()
        |> Program.add_relation("name", [:atom, :string])
        |> Program.add_relation("a_name", [:atom, :string])
        |> Program.add_rule(
          Rule.new(
            Atom.new("a_name", [Term.var("N"), Term.var("S")]),
            [{:positive, Atom.new("name", [Term.var("N"), Term.var("S")])}],
            [Constraint.starts_with(Term.var("S"), Term.const("A"))]
          )
        )

      assert {:ok, ir} = Compiler.compile(program)
      rule = hd(ir.rules)
      constraints = for {:constraint, c} <- rule.body, do: c
      assert length(constraints) == 1
      assert hd(constraints).op == :starts_with
    end

    test "compiles a rule with membership constraint" do
      program =
        Program.new()
        |> Program.add_relation("employee", [:atom, :atom])
        |> Program.add_relation("eng", [:atom])
        |> Program.add_rule(
          Rule.new(
            Atom.new("eng", [Term.var("X")]),
            [{:positive, Atom.new("employee", [Term.var("X"), Term.var("D")])}],
            [Constraint.member(Term.var("D"), Term.const([:engineering, :infra]))]
          )
        )

      assert {:ok, ir} = Compiler.compile(program)
      rule = hd(ir.rules)
      constraints = for {:constraint, c} <- rule.body, do: c
      assert length(constraints) == 1
      assert hd(constraints).op == :member
    end
  end

  describe "compile/1 fact value types" do
    test "compiles facts with integer values" do
      program =
        Program.new()
        |> Program.add_relation("age", [:atom, :integer])
        |> Program.add_fact("age", [:alice, 30])

      assert {:ok, ir} = Compiler.compile(program)
      fact = hd(ir.facts)
      assert fact.values == [{:atom, :alice}, {:int, 30}]
    end

    test "compiles facts with string values" do
      program =
        Program.new()
        |> Program.add_relation("label", [:string])
        |> Program.add_fact("label", ["hello"])

      assert {:ok, ir} = Compiler.compile(program)
      fact = hd(ir.facts)
      assert fact.values == [{:str, "hello"}]
    end

    test "compiles facts with atom values" do
      program =
        Program.new()
        |> Program.add_relation("parent", [:atom, :atom])
        |> Program.add_fact("parent", [:alice, :bob])

      assert {:ok, ir} = Compiler.compile(program)
      fact = hd(ir.facts)
      assert fact.values == [{:atom, :alice}, {:atom, :bob}]
    end

    test "facts are sorted deterministically" do
      program =
        Program.new()
        |> Program.add_relation("parent", [:atom, :atom])
        |> Program.add_fact("parent", [:z, :a])
        |> Program.add_fact("parent", [:a, :z])
        |> Program.add_fact("parent", [:m, :m])

      assert {:ok, ir} = Compiler.compile(program)
      values = Enum.map(ir.facts, & &1.values)
      assert values == [[{:atom, :a}, {:atom, :z}], [{:atom, :m}, {:atom, :m}], [{:atom, :z}, {:atom, :a}]]
    end
  end

  describe "compile/1 IR from_term list values" do
    test "IR.from_term converts const list with mixed types" do
      assert IR.from_term({:const, [1, :a, "hello"]}) == {:const, {:list, [{:int, 1}, {:atom, :a}, {:str, "hello"}]}}
    end

    test "IR.from_term converts const nested list" do
      assert IR.from_term({:const, [:x]}) == {:const, {:list, [{:atom, :x}]}}
    end

    test "IR.value_to_native converts list" do
      assert IR.value_to_native({:list, [{:int, 1}, {:atom, :foo}]}) == [1, :foo]
    end
  end

  describe "IR rule body ordering" do
    test "rules are sorted by (stratum, relation_name, rule_id)" do
      program =
        Program.new()
        |> Program.add_relation("a", [:atom])
        |> Program.add_relation("b", [:atom])
        |> Program.add_relation("c", [:atom])
        |> Program.add_rule(
          Rule.new(
            Atom.new("c", [Term.var("X")]),
            [{:positive, Atom.new("b", [Term.var("X")])}]
          )
        )
        |> Program.add_rule(
          Rule.new(
            Atom.new("b", [Term.var("X")]),
            [{:positive, Atom.new("a", [Term.var("X")])}]
          )
        )

      {:ok, ir} = Compiler.compile(program)

      rule_relations = Enum.map(ir.rules, & &1.head.relation)
      assert rule_relations == Enum.sort(rule_relations)
    end
  end
end
