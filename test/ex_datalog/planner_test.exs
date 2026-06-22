defmodule ExDatalog.PlannerTest do
  use ExUnit.Case, async: true

  doctest ExDatalog.Planner

  alias ExDatalog.{Atom, Compiler, Constraint, Planner, Program, Rule, Term}
  alias ExDatalog.Planner.{Join, Plan, Predicate, Stratum}

  defp transitive_ir do
    {:ok, ir} =
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
      |> Program.add_rule(
        Rule.new(
          Atom.new("path", [Term.var("X"), Term.var("Z")]),
          [
            {:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])},
            {:positive, Atom.new("path", [Term.var("Y"), Term.var("Z")])}
          ]
        )
      )
      |> Compiler.compile()

    ir
  end

  describe "plan/2" do
    test "produces a semi_naive plan by default" do
      {:ok, plan} = Planner.plan(transitive_ir())
      assert %Plan{strategy: :semi_naive} = plan
    end

    test "wraps IR strata into Stratum structs with rules" do
      {:ok, plan} = Planner.plan(transitive_ir())
      assert Enum.all?(plan.strata, &match?(%Stratum{}, &1))
      assert Enum.any?(plan.strata, fn s -> s.rules != [] end)
    end

    test "produces one join per positive body atom" do
      {:ok, plan} = Planner.plan(transitive_ir())
      # rule 1: 1 positive atom; rule 2: 2 positive atoms => 3 joins
      assert length(plan.joins) == 3
      assert Enum.all?(plan.joins, &match?(%Join{}, &1))
    end

    test "accepts the magic_sets strategy" do
      {:ok, plan} = Planner.plan(transitive_ir(), strategy: :magic_sets, goal: {"path", [:a, :_]})
      assert plan.strategy == :magic_sets
      assert plan.metadata.goal == {"path", [:a, :_]}
    end

    test "classifies comparison constraints as predicates" do
      {:ok, ir} =
        Program.new()
        |> Program.add_relation("income", [:atom, :integer])
        |> Program.add_relation("rich", [:atom])
        |> Program.add_fact("income", [:alice, 200_000])
        |> Program.add_rule(
          Rule.new(
            Atom.new("rich", [Term.var("P")]),
            [{:positive, Atom.new("income", [Term.var("P"), Term.var("S")])}],
            [Constraint.gt(Term.var("S"), Term.const(100_000))]
          )
        )
        |> Compiler.compile()

      {:ok, plan} = Planner.plan(ir)
      assert [%Predicate{kind: :comparison, op: :gt}] = plan.predicates
    end

    test "classifies aggregate constraints as aggregate predicates" do
      {:ok, ir} =
        Program.new()
        |> Program.add_relation("emp", [:atom, :atom])
        |> Program.add_relation("dept_count", [:atom, :integer])
        |> Program.add_fact("emp", [:alice, :eng])
        |> Program.add_rule(
          Rule.new(
            Atom.new("dept_count", [Term.var("D"), Term.var("N")]),
            [{:positive, Atom.new("emp", [Term.var("E"), Term.var("D")])}],
            [Constraint.count(Term.var("E"), Term.var("N"))]
          )
        )
        |> Compiler.compile()

      {:ok, plan} = Planner.plan(ir)
      assert [%Predicate{kind: :aggregate, op: :count}] = plan.predicates
    end
  end
end
