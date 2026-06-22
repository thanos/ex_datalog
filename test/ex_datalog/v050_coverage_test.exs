defmodule ExDatalog.V050CoverageTest do
  use ExUnit.Case, async: true

  alias ExDatalog.{Atom, Callback, Constraint, Constraints, IR, Rule, Term}
  alias ExDatalog.Planner.{Join, Plan, Predicate, Stratum}

  describe "planner structs" do
    test "structs hold their fields" do
      stratum = %Stratum{index: 0, rules: [], relations: ["edge"]}
      join = %Join{relation: "edge", position: 0}
      pred = %Predicate{kind: :comparison, op: :gt}

      plan = %Plan{strategy: :semi_naive, strata: [stratum], joins: [join], predicates: [pred]}

      assert plan.strategy == :semi_naive
      assert hd(plan.strata).relations == ["edge"]
      assert hd(plan.joins).relation == "edge"
      assert hd(plan.joins).strategy == :nested_loop
      assert hd(plan.predicates).kind == :comparison
    end
  end

  describe "Aggregate.evaluate/3 is not callable per-binding" do
    test "raises a clear error" do
      c = %IR.Constraint{op: :count, left: {:var, "X"}, right: nil, result: {:var, "N"}}

      assert_raise RuntimeError, ~r/not evaluated per-binding/, fn ->
        Constraints.Aggregate.evaluate(c, %{}, %ExDatalog.Constraint.Context{})
      end
    end
  end

  describe "Rule callback helpers" do
    test "has_callbacks?/1 and callbacks/1" do
      cb = Callback.new(String, :length, [Term.var("S")])

      rule =
        Rule.new(
          Atom.new("r", [Term.var("S")]),
          [{:positive, Atom.new("s", [Term.var("S")])}, {:callback, cb}]
        )

      assert Rule.has_callbacks?(rule)
      assert Rule.callbacks(rule) == [cb]
      assert "S" in Rule.variables(rule)
      assert Rule.body_atoms(rule) == [Atom.new("s", [Term.var("S")])]
    end

    test "value-returning callback contributes its result variable to variables/1" do
      cb = Callback.new(M, :f, [Term.var("X")], Term.var("R"))

      rule =
        Rule.new(
          Atom.new("r", [Term.var("X"), Term.var("R")]),
          [{:positive, Atom.new("s", [Term.var("X")])}, {:callback, cb}]
        )

      assert "R" in Rule.variables(rule)
    end
  end

  describe "Rule aggregate helpers" do
    test "aggregate_constraints/1 and non_aggregate_constraints/1 partition constraints" do
      agg = Constraint.count(Term.var("E"), Term.var("N"))
      cmp = Constraint.gt(Term.var("N"), Term.const(0))

      rule =
        Rule.new(
          Atom.new("r", [Term.var("D"), Term.var("N")]),
          [{:positive, Atom.new("emp", [Term.var("E"), Term.var("D")])}],
          [agg, cmp]
        )

      assert Rule.has_aggregates?(rule)
      assert Rule.aggregate_constraints(rule) == [agg]
      assert Rule.non_aggregate_constraints(rule) == [cmp]
    end
  end

  describe "Callback introspection" do
    test "input_variables/1 and result_variable/1" do
      cb = Callback.new(M, :f, [Term.var("A"), Term.const(1)], Term.var("R"))
      assert Callback.input_variables(cb) == ["A"]
      assert Callback.result_variable(cb) == "R"

      bool = Callback.new(M, :g, [Term.var("A")])
      assert Callback.result_variable(bool) == nil
    end
  end

  describe "Constraint aggregate op guards" do
    test "aggregate_op?/1 and aggregate?/1" do
      assert Constraint.aggregate_op?(:count)
      refute Constraint.aggregate_op?(:gt)
      assert Constraint.aggregate?(Constraint.sum(Term.var("X"), Term.var("T")))
    end

    test "min and max constructors" do
      assert %Constraint{op: :min} = Constraint.min(Term.var("X"), Term.var("V"))
      assert %Constraint{op: :max} = Constraint.max(Term.var("X"), Term.var("V"))
    end
  end
end
