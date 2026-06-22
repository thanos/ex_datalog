defmodule ExDatalog.AggregateTest do
  use ExUnit.Case, async: true

  alias ExDatalog.{Atom, Constraint, Knowledge, Program, Rule, Term}

  doctest ExDatalog.Constraints.Aggregate

  # --- Builder API evaluation ---

  defp count_program do
    Program.new()
    |> Program.add_relation("emp", [:atom, :atom])
    |> Program.add_relation("dept_count", [:atom, :integer])
    |> Program.add_fact("emp", [:alice, :eng])
    |> Program.add_fact("emp", [:bob, :eng])
    |> Program.add_fact("emp", [:carol, :ops])
    |> Program.add_rule(
      Rule.new(
        Atom.new("dept_count", [Term.var("D"), Term.var("N")]),
        [{:positive, Atom.new("emp", [Term.var("E"), Term.var("D")])}],
        [Constraint.count(Term.var("E"), Term.var("N"))]
      )
    )
  end

  describe "count aggregate" do
    test "counts members per group" do
      {:ok, knowledge} = ExDatalog.materialize(count_program())
      result = Knowledge.get(knowledge, "dept_count")
      assert MapSet.size(result) == 2
      assert {:eng, 2} in result
      assert {:ops, 1} in result
    end

    test "aggregate stratum terminates at fixpoint" do
      {:ok, knowledge} = ExDatalog.materialize(count_program())
      assert knowledge.stats.termination == :fixpoint
    end
  end

  describe "sum aggregate" do
    test "sums integer values per group" do
      program =
        Program.new()
        |> Program.add_relation("salary", [:atom, :atom, :integer])
        |> Program.add_relation("dept_total", [:atom, :integer])
        |> Program.add_fact("salary", [:alice, :eng, 100])
        |> Program.add_fact("salary", [:bob, :eng, 80])
        |> Program.add_fact("salary", [:carol, :ops, 50])
        |> Program.add_rule(
          Rule.new(
            Atom.new("dept_total", [Term.var("D"), Term.var("T")]),
            [{:positive, Atom.new("salary", [Term.var("E"), Term.var("D"), Term.var("A")])}],
            [Constraint.sum(Term.var("A"), Term.var("T"))]
          )
        )

      {:ok, knowledge} = ExDatalog.materialize(program)
      result = Knowledge.get(knowledge, "dept_total")
      assert {:eng, 180} in result
      assert {:ops, 50} in result
    end
  end

  describe "min and max aggregates" do
    defp score_program(op, head) do
      Program.new()
      |> Program.add_relation("score", [:atom, :atom, :integer])
      |> Program.add_relation(head, [:atom, :integer])
      |> Program.add_fact("score", [:alice, :eng, 90])
      |> Program.add_fact("score", [:bob, :eng, 70])
      |> Program.add_fact("score", [:carol, :ops, 60])
      |> Program.add_rule(
        Rule.new(
          Atom.new(head, [Term.var("D"), Term.var("V")]),
          [{:positive, Atom.new("score", [Term.var("E"), Term.var("D"), Term.var("S")])}],
          [apply(Constraint, op, [Term.var("S"), Term.var("V")])]
        )
      )
    end

    test "min picks the smallest per group" do
      {:ok, knowledge} = ExDatalog.materialize(score_program(:min, "lowest"))
      result = Knowledge.get(knowledge, "lowest")
      assert {:eng, 70} in result
      assert {:ops, 60} in result
    end

    test "max picks the largest per group" do
      {:ok, knowledge} = ExDatalog.materialize(score_program(:max, "highest"))
      result = Knowledge.get(knowledge, "highest")
      assert {:eng, 90} in result
      assert {:ops, 60} in result
    end
  end

  describe "aggregate with filter constraint" do
    test "filters bindings before grouping" do
      program =
        Program.new()
        |> Program.add_relation("score", [:atom, :atom, :integer])
        |> Program.add_relation("passing_count", [:atom, :integer])
        |> Program.add_fact("score", [:alice, :eng, 90])
        |> Program.add_fact("score", [:bob, :eng, 40])
        |> Program.add_fact("score", [:carol, :eng, 75])
        |> Program.add_rule(
          Rule.new(
            Atom.new("passing_count", [Term.var("D"), Term.var("N")]),
            [{:positive, Atom.new("score", [Term.var("E"), Term.var("D"), Term.var("S")])}],
            [
              Constraint.gte(Term.var("S"), Term.const(60)),
              Constraint.count(Term.var("E"), Term.var("N"))
            ]
          )
        )

      {:ok, knowledge} = ExDatalog.materialize(program)
      result = Knowledge.get(knowledge, "passing_count")
      assert {:eng, 2} in result
    end
  end

  describe "aggregate validation" do
    test "rejects more than one aggregate per rule" do
      program =
        Program.new()
        |> Program.add_relation("emp", [:atom, :atom, :integer])
        |> Program.add_relation("stats", [:atom, :integer, :integer])
        |> Program.add_rule(
          Rule.new(
            Atom.new("stats", [Term.var("D"), Term.var("N"), Term.var("T")]),
            [{:positive, Atom.new("emp", [Term.var("E"), Term.var("D"), Term.var("A")])}],
            [
              Constraint.count(Term.var("E"), Term.var("N")),
              Constraint.sum(Term.var("A"), Term.var("T"))
            ]
          )
        )

      assert {:error, errors} = ExDatalog.materialize(program)
      assert Enum.any?(errors, fn e -> e.kind == :multiple_aggregates end)
    end

    test "rejects aggregate over a self-recursive relation" do
      program =
        Program.new()
        |> Program.add_relation("path", [:atom, :integer])
        |> Program.add_rule(
          Rule.new(
            Atom.new("path", [Term.var("X"), Term.var("N")]),
            [{:positive, Atom.new("path", [Term.var("X"), Term.var("Y")])}],
            [Constraint.count(Term.var("Y"), Term.var("N"))]
          )
        )

      assert {:error, errors} = ExDatalog.materialize(program)
      assert Enum.any?(errors, fn e -> e.kind == :aggregate_in_recursion end)
    end

    test "rejects unbound aggregate input variable" do
      program =
        Program.new()
        |> Program.add_relation("emp", [:atom, :atom])
        |> Program.add_relation("dept_count", [:atom, :integer])
        |> Program.add_rule(
          Rule.new(
            Atom.new("dept_count", [Term.var("D"), Term.var("N")]),
            [{:positive, Atom.new("emp", [Term.var("E"), Term.var("D")])}],
            # Z is not bound by any positive body atom
            [Constraint.count(Term.var("Z"), Term.var("N"))]
          )
        )

      assert {:error, errors} = ExDatalog.materialize(program)
      assert Enum.any?(errors, fn e -> e.kind == :unbound_constraint_variable end)
    end

    test "rejects aggregate whose result variable is not in the head" do
      program =
        Program.new()
        |> Program.add_relation("emp", [:atom, :atom])
        |> Program.add_relation("dept_count", [:atom])
        |> Program.add_rule(
          Rule.new(
            # head is [D] only; the aggregate result N is missing
            Atom.new("dept_count", [Term.var("D")]),
            [{:positive, Atom.new("emp", [Term.var("E"), Term.var("D")])}],
            [Constraint.count(Term.var("E"), Term.var("N"))]
          )
        )

      assert {:error, errors} = ExDatalog.materialize(program)
      assert Enum.any?(errors, fn e -> e.kind == :aggregate_result_not_in_head end)
    end
  end

  describe "aggregate integer-input guards" do
    defp non_integer_agg_program(agg_constraint) do
      Program.new()
      |> Program.add_relation("sal", [:atom, :atom])
      |> Program.add_relation("total", [:atom, :atom])
      |> Program.add_fact("sal", [:eng, :not_a_number])
      |> Program.add_rule(
        Rule.new(
          Atom.new("total", [Term.var("D"), Term.var("T")]),
          [{:positive, Atom.new("sal", [Term.var("D"), Term.var("A")])}],
          [agg_constraint]
        )
      )
    end

    test "sum raises ArgumentError on a non-integer input" do
      program = non_integer_agg_program(Constraint.sum(Term.var("A"), Term.var("T")))

      assert_raise ArgumentError, ~r/sum aggregate requires integer inputs/, fn ->
        ExDatalog.materialize(program)
      end
    end

    test "min raises ArgumentError on a non-integer input" do
      program = non_integer_agg_program(Constraint.min(Term.var("A"), Term.var("T")))

      assert_raise ArgumentError, ~r/min aggregate requires integer inputs/, fn ->
        ExDatalog.materialize(program)
      end
    end

    test "max raises ArgumentError on a non-integer input" do
      program = non_integer_agg_program(Constraint.max(Term.var("A"), Term.var("T")))

      assert_raise ArgumentError, ~r/max aggregate requires integer inputs/, fn ->
        ExDatalog.materialize(program)
      end
    end

    test "count accepts non-integer inputs (counts group size)" do
      program =
        Program.new()
        |> Program.add_relation("item", [:atom, :atom])
        |> Program.add_relation("item_count", [:atom, :integer])
        |> Program.add_fact("item", [:box, :red])
        |> Program.add_fact("item", [:box, :blue])
        |> Program.add_rule(
          Rule.new(
            Atom.new("item_count", [Term.var("B"), Term.var("N")]),
            [{:positive, Atom.new("item", [Term.var("B"), Term.var("C")])}],
            [Constraint.count(Term.var("C"), Term.var("N"))]
          )
        )

      assert {:ok, knowledge} = ExDatalog.materialize(program)
      assert {:box, 2} in Knowledge.get(knowledge, "item_count")
    end
  end

  describe "aggregate stratification" do
    test "aggregate over a derived relation is placed in a higher stratum" do
      # base -> mid (derived) -> count over mid
      program =
        Program.new()
        |> Program.add_relation("base", [:atom, :atom])
        |> Program.add_relation("mid", [:atom, :atom])
        |> Program.add_relation("mid_count", [:atom, :integer])
        |> Program.add_fact("base", [:a, :x])
        |> Program.add_fact("base", [:a, :y])
        |> Program.add_fact("base", [:b, :z])
        |> Program.add_rule(
          Rule.new(
            Atom.new("mid", [Term.var("K"), Term.var("V")]),
            [{:positive, Atom.new("base", [Term.var("K"), Term.var("V")])}]
          )
        )
        |> Program.add_rule(
          Rule.new(
            Atom.new("mid_count", [Term.var("K"), Term.var("N")]),
            [{:positive, Atom.new("mid", [Term.var("K"), Term.var("V")])}],
            [Constraint.count(Term.var("V"), Term.var("N"))]
          )
        )

      {:ok, ir} = ExDatalog.compile(program)
      mid_stratum = Enum.find(ir.rules, fn r -> r.head.relation == "mid" end).stratum
      count_stratum = Enum.find(ir.rules, fn r -> r.head.relation == "mid_count" end).stratum
      assert count_stratum > mid_stratum

      {:ok, knowledge} = ExDatalog.materialize(program)
      result = Knowledge.get(knowledge, "mid_count")
      assert {:a, 2} in result
      assert {:b, 1} in result
    end
  end

  describe "aggregate via from_tuple" do
    test "builds aggregate constraints" do
      assert %Constraint{op: :count, left: {:var, "X"}, right: nil, result: {:var, "N"}} =
               Constraint.from_tuple({:count, {:var, "X"}, {:var, "N"}})

      assert %Constraint{op: :sum, result: {:var, "T"}} =
               Constraint.from_tuple({:sum, :A, :T})
    end

    test "valid? accepts aggregate constraints" do
      assert Constraint.valid?(Constraint.count(Term.var("X"), Term.var("N")))
      assert Constraint.valid?(Constraint.sum(Term.var("X"), Term.var("T")))
    end
  end
end
