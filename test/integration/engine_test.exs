defmodule ExDatalog.IntegrationTest do
  use ExUnit.Case, async: true

  alias ExDatalog.{Atom, Constraint, Program, Rule, Term}

  describe "end-to-end: positive rules" do
    test "transitive closure: ancestor from parent" do
      result =
        Program.new()
        |> Program.add_relation("parent", [:atom, :atom])
        |> Program.add_relation("ancestor", [:atom, :atom])
        |> Program.add_fact("parent", [:alice, :bob])
        |> Program.add_fact("parent", [:bob, :carol])
        |> Program.add_fact("parent", [:carol, :dave])
        |> Program.add_rule(
          Rule.new(
            Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
            [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
          )
        )
        |> Program.add_rule(
          Rule.new(
            Atom.new("ancestor", [Term.var("X"), Term.var("Z")]),
            [
              {:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])},
              {:positive, Atom.new("ancestor", [Term.var("Y"), Term.var("Z")])}
            ]
          )
        )
        |> ExDatalog.query()

      assert {:ok, result} = result

      ancestor = ExDatalog.Result.get(result, "ancestor")
      assert MapSet.size(ancestor) == 6

      assert {:alice, :bob} in ancestor
      assert {:bob, :carol} in ancestor
      assert {:carol, :dave} in ancestor
      assert {:alice, :carol} in ancestor
      assert {:bob, :dave} in ancestor
      assert {:alice, :dave} in ancestor
    end

    test "single-rule with base facts" do
      result =
        Program.new()
        |> Program.add_relation("edge", [:atom, :atom])
        |> Program.add_relation("path", [:atom, :atom])
        |> Program.add_fact("edge", [:a, :b])
        |> Program.add_fact("edge", [:b, :c])
        |> Program.add_rule(
          Rule.new(
            Atom.new("path", [Term.var("X"), Term.var("Y")]),
            [{:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}]
          )
        )
        |> ExDatalog.query()

      assert {:ok, result} = result
      path = ExDatalog.Result.get(result, "path")
      assert MapSet.size(path) == 2
      assert {:a, :b} in path
      assert {:b, :c} in path
    end

    test "empty program with only facts" do
      result =
        Program.new()
        |> Program.add_relation("person", [:atom])
        |> Program.add_fact("person", [:alice])
        |> Program.add_fact("person", [:bob])
        |> ExDatalog.query()

      assert {:ok, result} = result
      person = ExDatalog.Result.get(result, "person")
      assert MapSet.size(person) == 2
    end

    test "multi-join: three-body-atom rule" do
      result =
        Program.new()
        |> Program.add_relation("link", [:atom, :atom])
        |> Program.add_relation("path3", [:atom, :atom, :atom])
        |> Program.add_fact("link", [:a, :b])
        |> Program.add_fact("link", [:b, :c])
        |> Program.add_fact("link", [:c, :d])
        |> Program.add_rule(
          Rule.new(
            Atom.new("path3", [Term.var("X"), Term.var("Y"), Term.var("Z")]),
            [
              {:positive, Atom.new("link", [Term.var("X"), Term.var("Y")])},
              {:positive, Atom.new("link", [Term.var("Y"), Term.var("Z")])},
              {:positive, Atom.new("link", [Term.var("Z"), Term.var("W")])}
            ]
          )
        )
        |> ExDatalog.query()

      assert {:ok, result} = result
      path3 = ExDatalog.Result.get(result, "path3")
      assert MapSet.size(path3) == 1
      assert {:a, :b, :c} in path3
    end
  end

  describe "end-to-end: constraints" do
    test "comparison constraint filters results" do
      result =
        Program.new()
        |> Program.add_relation("value", [:atom, :integer])
        |> Program.add_relation("big_value", [:atom, :integer])
        |> Program.add_fact("value", [:x, 3])
        |> Program.add_fact("value", [:y, 10])
        |> Program.add_fact("value", [:z, 5])
        |> Program.add_rule(
          Rule.new(
            Atom.new("big_value", [Term.var("N"), Term.var("V")]),
            [{:positive, Atom.new("value", [Term.var("N"), Term.var("V")])}],
            [Constraint.gt(Term.var("V"), Term.const(5))]
          )
        )
        |> ExDatalog.query()

      assert {:ok, result} = result
      big = ExDatalog.Result.get(result, "big_value")
      assert MapSet.size(big) == 1
      assert {:y, 10} in big
    end

    test "arithmetic constraint binds result" do
      result =
        Program.new()
        |> Program.add_relation("pair", [:integer, :integer])
        |> Program.add_relation("sum", [:integer, :integer, :integer])
        |> Program.add_fact("pair", [3, 7])
        |> Program.add_rule(
          Rule.new(
            Atom.new("sum", [Term.var("A"), Term.var("B"), Term.var("C")]),
            [{:positive, Atom.new("pair", [Term.var("A"), Term.var("B")])}],
            [Constraint.add(Term.var("A"), Term.var("B"), Term.var("C"))]
          )
        )
        |> ExDatalog.query()

      assert {:ok, result} = result
      sums = ExDatalog.Result.get(result, "sum")
      assert MapSet.size(sums) == 1
      assert {3, 7, 10} in sums
    end

    test "equality constraint" do
      result =
        Program.new()
        |> Program.add_relation("edge", [:atom, :atom])
        |> Program.add_relation("cycle", [:atom])
        |> Program.add_fact("edge", [:a, :a])
        |> Program.add_fact("edge", [:a, :b])
        |> Program.add_rule(
          Rule.new(
            Atom.new("cycle", [Term.var("X")]),
            [
              {:positive, Atom.new("edge", [Term.var("X"), Term.var("X")])}
            ]
          )
        )
        |> ExDatalog.query()

      assert {:ok, result} = result
      cycle = ExDatalog.Result.get(result, "cycle")
      assert MapSet.size(cycle) == 1
      assert {:a} in cycle
    end
  end

  describe "end-to-end: Result API" do
    test "query with goal option" do
      result =
        Program.new()
        |> Program.add_relation("edge", [:atom, :atom])
        |> Program.add_relation("path", [:atom, :atom])
        |> Program.add_fact("edge", [:a, :b])
        |> Program.add_fact("edge", [:b, :c])
        |> Program.add_rule(
          Rule.new(
            Atom.new("path", [Term.var("X"), Term.var("Y")]),
            [{:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}]
          )
        )
        |> ExDatalog.query()

      assert {:ok, result} = result
      path = ExDatalog.Result.get(result, "path")
      assert MapSet.size(path) == 2

      matched = ExDatalog.Result.match(result, "path", [:a, :_])
      assert MapSet.size(matched) == 1
      assert {:a, :b} in matched
    end
  end

  describe "end-to-end: validation errors" do
    test "invalid program returns error from query" do
      program =
        Program.new()
        |> Program.add_relation("edge", [:atom, :atom])

      rule =
        Rule.new(
          Atom.new("path", [Term.var("X"), Term.var("Y")]),
          [{:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}]
        )

      assert {:ok, _} = ExDatalog.validate(program)

      invalid_program = Map.put(program, :rules, [rule])
      assert {:error, _errors} = ExDatalog.validate(invalid_program)
    end
  end

  describe "end-to-end: strata" do
    test "multi-stratum program evaluates correctly" do
      result =
        Program.new()
        |> Program.add_relation("edge", [:atom, :atom])
        |> Program.add_relation("path", [:atom, :atom])
        |> Program.add_fact("edge", [:a, :b])
        |> Program.add_fact("edge", [:b, :c])
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
        |> ExDatalog.query()

      assert {:ok, result} = result
      path = ExDatalog.Result.get(result, "path")
      assert {:a, :b} in path
      assert {:b, :c} in path
      assert {:a, :c} in path
    end
  end
end
