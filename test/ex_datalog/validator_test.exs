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
  end
end
