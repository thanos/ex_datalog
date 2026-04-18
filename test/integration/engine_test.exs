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

  describe "end-to-end: negation" do
    test "bachelor example with stratified negation" do
      # bachelor(X) :- male(X), not married(X, _).
      # male = {alice, bob}, married = {(alice, carol)}.
      # Only bob is a bachelor.
      result =
        Program.new()
        |> Program.add_relation("male", [:atom])
        |> Program.add_relation("married", [:atom, :atom])
        |> Program.add_relation("bachelor", [:atom])
        |> Program.add_fact("male", [:alice])
        |> Program.add_fact("male", [:bob])
        |> Program.add_fact("married", [:alice, :carol])
        |> Program.add_rule(
          Rule.new(
            Atom.new("bachelor", [Term.var("X")]),
            [
              {:positive, Atom.new("male", [Term.var("X")])},
              {:negative, Atom.new("married", [Term.var("X"), Term.wildcard()])}
            ]
          )
        )
        |> ExDatalog.query()

      assert {:ok, result} = result
      bachelors = ExDatalog.Result.get(result, "bachelor")
      assert MapSet.size(bachelors) == 1
      assert {:bob} in bachelors
    end

    test "negation with empty relation passes all bindings" do
      # If no one is married, all males are bachelors.
      result =
        Program.new()
        |> Program.add_relation("male", [:atom])
        |> Program.add_relation("married", [:atom, :atom])
        |> Program.add_relation("bachelor", [:atom])
        |> Program.add_fact("male", [:alice])
        |> Program.add_fact("male", [:bob])
        |> Program.add_rule(
          Rule.new(
            Atom.new("bachelor", [Term.var("X")]),
            [
              {:positive, Atom.new("male", [Term.var("X")])},
              {:negative, Atom.new("married", [Term.var("X"), Term.wildcard()])}
            ]
          )
        )
        |> ExDatalog.query()

      assert {:ok, result} = result
      bachelors = ExDatalog.Result.get(result, "bachelor")
      assert MapSet.size(bachelors) == 2
      assert {:alice} in bachelors
      assert {:bob} in bachelors
    end

    test "negation with constant in negative atom" do
      # not_married_to_alice(X) :- male(X), not married(X, alice).
      result =
        Program.new()
        |> Program.add_relation("male", [:atom])
        |> Program.add_relation("married", [:atom, :atom])
        |> Program.add_relation("not_married_to_alice", [:atom])
        |> Program.add_fact("male", [:bob])
        |> Program.add_fact("male", [:carol])
        |> Program.add_fact("married", [:bob, :alice])
        |> Program.add_rule(
          Rule.new(
            Atom.new("not_married_to_alice", [Term.var("X")]),
            [
              {:positive, Atom.new("male", [Term.var("X")])},
              {:negative, Atom.new("married", [Term.var("X"), Term.const(:alice)])}
            ]
          )
        )
        |> ExDatalog.query()

      assert {:ok, result} = result
      filtered = ExDatalog.Result.get(result, "not_married_to_alice")
      assert MapSet.size(filtered) == 1
      assert {:carol} in filtered
    end

    test "multiple negative atoms" do
      # verified(X) :- candidate(X), not blocked(X), not rejected(X).
      result =
        Program.new()
        |> Program.add_relation("candidate", [:atom])
        |> Program.add_relation("blocked", [:atom])
        |> Program.add_relation("rejected", [:atom])
        |> Program.add_relation("verified", [:atom])
        |> Program.add_fact("candidate", [:alice])
        |> Program.add_fact("candidate", [:bob])
        |> Program.add_fact("candidate", [:carol])
        |> Program.add_fact("blocked", [:bob])
        |> Program.add_fact("rejected", [:carol])
        |> Program.add_rule(
          Rule.new(
            Atom.new("verified", [Term.var("X")]),
            [
              {:positive, Atom.new("candidate", [Term.var("X")])},
              {:negative, Atom.new("blocked", [Term.var("X")])},
              {:negative, Atom.new("rejected", [Term.var("X")])}
            ]
          )
        )
        |> ExDatalog.query()

      assert {:ok, result} = result
      verified = ExDatalog.Result.get(result, "verified")
      assert MapSet.size(verified) == 1
      assert {:alice} in verified
    end

    test "negation with recursive positive rule and negation in separate stratum" do
      # reachable(X, Y) :- edge(X, Y).
      # reachable(X, Z) :- edge(X, Y), reachable(Y, Z).
      # unreachable(X, Y) :- node(X), node(Y), not reachable(X, Y).
      # node = {a, b, c}, edge = {(a, b), (b, c)}.
      # reachable = {(a, b), (b, c), (a, c)}.
      # unreachable pairs: {(a, a), (b, b), (c, c), (b, a), (c, a), (c, b)}.
      result =
        Program.new()
        |> Program.add_relation("node", [:atom])
        |> Program.add_relation("edge", [:atom, :atom])
        |> Program.add_relation("reachable", [:atom, :atom])
        |> Program.add_relation("unreachable", [:atom, :atom])
        |> Program.add_fact("node", [:a])
        |> Program.add_fact("node", [:b])
        |> Program.add_fact("node", [:c])
        |> Program.add_fact("edge", [:a, :b])
        |> Program.add_fact("edge", [:b, :c])
        |> Program.add_rule(
          Rule.new(
            Atom.new("reachable", [Term.var("X"), Term.var("Y")]),
            [{:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}]
          )
        )
        |> Program.add_rule(
          Rule.new(
            Atom.new("reachable", [Term.var("X"), Term.var("Z")]),
            [
              {:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])},
              {:positive, Atom.new("reachable", [Term.var("Y"), Term.var("Z")])}
            ]
          )
        )
        |> Program.add_rule(
          Rule.new(
            Atom.new("unreachable", [Term.var("X"), Term.var("Y")]),
            [
              {:positive, Atom.new("node", [Term.var("X")])},
              {:positive, Atom.new("node", [Term.var("Y")])},
              {:negative, Atom.new("reachable", [Term.var("X"), Term.var("Y")])}
            ]
          )
        )
        |> ExDatalog.query()

      assert {:ok, result} = result

      reachable = ExDatalog.Result.get(result, "reachable")
      assert {:a, :b} in reachable
      assert {:b, :c} in reachable
      assert {:a, :c} in reachable

      unreachable = ExDatalog.Result.get(result, "unreachable")

      assert {:b, :a} in unreachable
      assert {:c, :a} in unreachable
      assert {:c, :b} in unreachable
    end

    test "unstratifiable negation is rejected by validator" do
      # p(X) :- not p(X). — this is unstratifiable.
      program =
        Program.new()
        |> Program.add_relation("p", [:atom])
        |> Program.add_rule(
          Rule.new(
            Atom.new("p", [Term.var("X")]),
            [{:negative, Atom.new("p", [Term.var("X")])}]
          )
        )

      assert {:error, _errors} = ExDatalog.validate(program)
    end

    test "engine rejects directly-constructed unstratifiable IR" do
      alias ExDatalog.IR

      ir = %IR{
        relations: [
          %IR.Relation{name: "p", arity: 1, types: [:atom]}
        ],
        facts: [],
        rules: [
          %IR.Rule{
            id: 0,
            head: %IR.Atom{relation: "p", terms: [{:var, "X"}]},
            body: [{:negative, %IR.Atom{relation: "p", terms: [{:var, "X"}]}}],
            stratum: 0,
            metadata: %{}
          }
        ],
        strata: [%IR.Stratum{index: 0, rule_ids: [0], relations: ["p"]}]
      }

      assert {:error, message} = ExDatalog.evaluate(ir)
      assert message =~ "unstratifiable negation"
    end
  end
end
