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

  describe "IR rule ordering" do
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
