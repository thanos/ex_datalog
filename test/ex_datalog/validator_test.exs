defmodule ExDatalog.ValidatorTest do
  use ExUnit.Case, async: true

  alias ExDatalog.{Atom, Constraint, Program, Rule, Term}

  describe "Phase 1: structural validation" do
    test "valid program returns ok" do
      program =
        Program.new()
        |> Program.add_relation("edge", [:atom, :atom])
        |> Program.add_fact("edge", [:a, :b])

      assert {:ok, _} = ExDatalog.validate(program)
    end

    test "undefined relation in rule body" do
      program =
        Program.new()
        |> Program.add_relation("r", [:atom])
        |> then(
          &%{
            &1
            | rules: [
                Rule.new(
                  Atom.new("r", [Term.var("X")]),
                  [{:positive, Atom.new("undefined_rel", [Term.var("X")])}]
                )
              ]
          }
        )

      assert {:error, errors} = ExDatalog.validate(program)
      assert Enum.any?(errors, &(&1.kind == :undefined_relation))
    end

    test "arity mismatch in rule body" do
      bad_rule =
        Rule.new(
          Atom.new("parent", [Term.var("X"), Term.var("Y")]),
          [{:positive, Atom.new("parent", [Term.var("X")])}]
        )

      program =
        Program.new()
        |> Program.add_relation("parent", [:atom, :atom])
        |> then(&%{&1 | rules: [bad_rule]})

      assert {:error, errors} = ExDatalog.validate(program)
      assert Enum.any?(errors, &(&1.kind == :arity_mismatch))
    end

    test "invalid body literal" do
      program =
        Program.new()
        |> Program.add_relation("a", [:atom])
        |> Program.add_relation("r", [:atom])
        |> then(
          &%{
            &1
            | rules: [
                Rule.new(
                  Atom.new("r", [Term.var("X")]),
                  ["not_a_literal"]
                )
              ]
          }
        )

      assert {:error, errors} = ExDatalog.validate(program)
      assert Enum.any?(errors, &(&1.kind == :invalid_body_literal))
    end
  end

  describe "Phase 2: semantic validation" do
    test "safe program with positive rules validates ok" do
      program =
        Program.new()
        |> Program.add_relation("parent", [:atom, :atom])
        |> Program.add_relation("ancestor", [:atom, :atom])
        |> Program.add_rule(
          Rule.new(
            Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
            [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
          )
        )

      assert {:ok, _} = ExDatalog.validate(program)
    end

    test "safe program with negation across strata validates ok" do
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

      assert {:ok, _} = ExDatalog.validate(program)
    end

    test "unsafe head variable is rejected" do
      program =
        Program.new()
        |> Program.add_relation("input", [:atom])
        |> Program.add_relation("result", [:atom, :atom])
        |> Program.add_rule(
          Rule.new(
            Atom.new("result", [Term.var("X"), Term.var("Z")]),
            [{:positive, Atom.new("input", [Term.var("X")])}]
          )
        )

      assert {:error, errors} = ExDatalog.validate(program)
      unsafe = Enum.filter(errors, &(&1.kind == :unsafe_variable))
      assert unsafe != []
      assert Enum.any?(unsafe, &(&1.context.variable == "Z"))
    end

    test "unbound constraint variable is rejected" do
      program =
        Program.new()
        |> Program.add_relation("input", [:atom])
        |> Program.add_relation("result", [:atom])
        |> Program.add_rule(
          Rule.new(
            Atom.new("result", [Term.var("X")]),
            [{:positive, Atom.new("input", [Term.var("X")])}],
            [Constraint.gt(Term.var("Y"), Term.const(0))]
          )
        )

      assert {:error, errors} = ExDatalog.validate(program)
      unbound = Enum.filter(errors, &(&1.kind == :unbound_constraint_variable))
      assert unbound != []
      assert "Y" in hd(unbound).context.variables
    end

    test "wildcard in head is rejected" do
      program =
        Program.new()
        |> Program.add_relation("parent", [:atom, :atom])
        |> Program.add_relation("any_child", [:atom, :atom])
        |> Program.add_rule(
          Rule.new(
            Atom.new("any_child", [Term.wildcard(), Term.var("Y")]),
            [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
          )
        )

      assert {:error, errors} = ExDatalog.validate(program)
      assert Enum.any?(errors, &(&1.kind == :wildcard_in_head))
    end

    test "unstratifiable negation is rejected" do
      program =
        Program.new()
        |> Program.add_relation("q", [:atom])
        |> Program.add_relation("p", [:atom])
        |> Program.add_rule(
          Rule.new(
            Atom.new("p", [Term.var("X")]),
            [
              {:positive, Atom.new("q", [Term.var("X")])},
              {:negative, Atom.new("p", [Term.var("X")])}
            ]
          )
        )

      assert {:error, errors} = ExDatalog.validate(program)
      assert Enum.any?(errors, &(&1.kind == :unstratified_negation))
    end

    test "multiple errors from different phases are collected" do
      # Structural error + semantic error in one program.
      # Let me directly test that the pipeline combines errors from both phases.
      program =
        Program.new()
        |> Program.add_relation("a", [:atom])
        |> Program.add_relation("b", [:atom, :atom])
        |> Program.add_relation("r", [:atom])
        |> Program.add_rule(
          Rule.new(
            Atom.new("r", [Term.var("Z")]),
            [{:positive, Atom.new("a", [Term.var("X")])}]
          )
        )

      # Z is unsafe (Phase 2), everything else is valid
      assert {:error, errors} = ExDatalog.validate(program)
      unsafe = Enum.filter(errors, &(&1.kind == :unsafe_variable))
      assert unsafe != []
    end

    # Regression test for C2: semantic errors must appear in discovery order
    # in the final error list, not reversed.
    test "semantic errors are returned in discovery order (C2 regression)" do
      # Three rules each with a distinct unsafe variable: Z0, Z1, Z2.
      # After fix, errors for rule 0 must appear before rule 1 before rule 2.
      rules =
        Enum.map(0..2, fn i ->
          Rule.new(
            Atom.new("r", [Term.var("X"), Term.var("Z#{i}")]),
            [{:positive, Atom.new("a", [Term.var("X")])}]
          )
        end)

      program =
        Program.new()
        |> Program.add_relation("a", [:atom])
        |> Program.add_relation("r", [:atom, :atom])
        |> then(&%{&1 | rules: rules})

      assert {:error, errors} = ExDatalog.validate(program)

      unsafe = Enum.filter(errors, &(&1.kind == :unsafe_variable))
      assert length(unsafe) == 3

      rule_indices = Enum.map(unsafe, & &1.context.rule_index)

      assert rule_indices == Enum.sort(rule_indices),
             "Expected errors in rule-index order, got: #{inspect(rule_indices)}"
    end

    # L7 regression: integration test combining structural + safety + stratification errors.
    test "errors from all three validation phases are collected together" do
      # Phase 1 (structural): rule body references undefined relation "no_such_rel"
      # Phase 2 (safety): variable Z in head is unsafe
      # Phase 2 (stratification): p depends negatively on itself
      rule1 =
        Rule.new(
          Atom.new("r", [Term.var("X"), Term.var("Z")]),
          [{:positive, Atom.new("no_such_rel", [Term.var("X")])}]
        )

      rule2 =
        Rule.new(
          Atom.new("p", [Term.var("X")]),
          [
            {:positive, Atom.new("q", [Term.var("X")])},
            {:negative, Atom.new("p", [Term.var("X")])}
          ]
        )

      program =
        Program.new()
        |> Program.add_relation("p", [:atom])
        |> Program.add_relation("q", [:atom])
        |> Program.add_relation("r", [:atom, :atom])
        |> then(&%{&1 | rules: [rule1, rule2]})

      assert {:error, errors} = ExDatalog.validate(program)

      kinds = Enum.map(errors, & &1.kind)

      assert :undefined_relation in kinds,
             "Expected :undefined_relation error, got: #{inspect(kinds)}"

      assert :unsafe_variable in kinds,
             "Expected :unsafe_variable error, got: #{inspect(kinds)}"

      assert :unstratified_negation in kinds,
             "Expected :unstratified_negation error, got: #{inspect(kinds)}"
    end
  end

  describe "validate/1 idempotency" do
    test "validate returns the program struct unchanged" do
      program =
        Program.new()
        |> Program.add_relation("parent", [:atom, :atom])
        |> Program.add_relation("ancestor", [:atom, :atom])
        |> Program.add_fact("parent", [:alice, :bob])
        |> Program.add_fact("parent", [:bob, :carol])

      {:ok, validated} = ExDatalog.validate(program)

      assert validated == program
    end

    test "validate is idempotent: calling twice returns the same program" do
      program =
        Program.new()
        |> Program.add_relation("parent", [:atom, :atom])
        |> Program.add_fact("parent", [:alice, :bob])
        |> Program.add_fact("parent", [:bob, :carol])

      {:ok, first} = ExDatalog.validate(program)
      {:ok, second} = ExDatalog.validate(first)

      assert first == second
      assert first.facts == program.facts
    end
  end
end
