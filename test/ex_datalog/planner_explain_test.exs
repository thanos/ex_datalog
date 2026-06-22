defmodule ExDatalog.PlannerExplainTest do
  use ExUnit.Case, async: true

  alias ExDatalog.{Atom, Planner, Program, Rule, Term}

  defp transitive_program do
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
  end

  describe "explain_plan/1,2" do
    test "describes the strategy" do
      assert Planner.explain_plan(transitive_program()) =~ "Strategy: semi_naive"
    end

    test "lists strata" do
      output = Planner.explain_plan(transitive_program())
      assert output =~ "Stratum 0"
    end

    test "reports join and predicate counts" do
      output = Planner.explain_plan(transitive_program())
      assert output =~ "Joins: 1"
      assert output =~ "Predicates: 0"
    end

    test "honours the magic_sets strategy option" do
      output =
        Planner.explain_plan(transitive_program(),
          strategy: :magic_sets,
          goal: {"path", [:a, :_]}
        )

      assert output =~ "Strategy: magic_sets"
    end

    test "returns an error string for an invalid program" do
      bad =
        Program.new()
        |> Program.add_relation("path", [:atom, :atom])
        |> Program.add_rule(
          Rule.new(
            # Z is unsafe — not bound by any positive body atom
            Atom.new("path", [Term.var("X"), Term.var("Z")]),
            [{:positive, Atom.new("path", [Term.var("X"), Term.var("Y")])}]
          )
        )

      assert Planner.explain_plan(bad) =~ "compilation failed"
    end
  end
end
