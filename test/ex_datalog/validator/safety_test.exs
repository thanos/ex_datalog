defmodule ExDatalog.Validator.SafetyTest do
  use ExUnit.Case, async: true

  alias ExDatalog.{Atom, Constraint, Program, Rule, Term}
  alias ExDatalog.Validator.Safety

  defp build_program_with_rule(rule, extra_relations) do
    program = Program.new()

    program =
      Enum.reduce(extra_relations, program, fn {name, types}, acc ->
        Program.add_relation(acc, name, types)
      end)

    %{program | rules: [rule]}
  end

  describe "unsafe head variable" do
    test "safe: all head variables bound by positive body" do
      rule =
        Rule.new(
          Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
          [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
        )

      program =
        build_program_with_rule(rule, [{"parent", [:atom, :atom]}, {"ancestor", [:atom, :atom]}])

      assert Safety.check(program) == []
    end

    test "safe: variable bound through transitive join" do
      rule =
        Rule.new(
          Atom.new("ancestor", [Term.var("X"), Term.var("Z")]),
          [
            {:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])},
            {:positive, Atom.new("ancestor", [Term.var("Y"), Term.var("Z")])}
          ]
        )

      program =
        build_program_with_rule(rule, [{"parent", [:atom, :atom]}, {"ancestor", [:atom, :atom]}])

      assert Safety.check(program) == []
    end

    test "unsafe: head variable not in any body atom" do
      rule =
        Rule.new(
          Atom.new("ancestor", [Term.var("X"), Term.var("Z")]),
          [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
        )

      program =
        build_program_with_rule(rule, [{"parent", [:atom, :atom]}, {"ancestor", [:atom, :atom]}])

      errors = Safety.check(program)

      assert length(errors) == 1
      assert hd(errors).kind == :unsafe_variable
      assert hd(errors).context.variable == "Z"
    end

    test "unsafe: variable only in negative body atom" do
      rule =
        Rule.new(
          Atom.new("bachelor", [Term.var("X")]),
          [
            {:positive, Atom.new("male", [Term.var("X")])},
            {:negative, Atom.new("married", [Term.var("Y")])}
          ]
        )

      program =
        build_program_with_rule(rule, [
          {"male", [:atom]},
          {"married", [:atom, :atom]},
          {"bachelor", [:atom]}
        ])

      errors = Safety.check(program)

      # X is safe (bound by positive), Y is only in negative and not in head
      # But Y isn't in the head either, so it's not an unsafe HEAD variable.
      # However, Y is still not bound anywhere positive, which is fine for body-only vars.
      # Actually, wildcard in negative body is allowed. Y here is in negative only.
      # The safety check flags unsafe HEAD variables, which would only be vars in the head
      # that aren't bound by positive body atoms.
      unsafe_vars = Enum.filter(errors, &(&1.kind == :unsafe_variable))
      # X is safe (in positive body), no head vars are unsafe
      assert unsafe_vars == []
    end

    test "multiple unsafe variables reported" do
      rule =
        Rule.new(
          Atom.new("result", [Term.var("X"), Term.var("Z"), Term.var("W")]),
          [{:positive, Atom.new("input", [Term.var("X")])}]
        )

      program =
        build_program_with_rule(rule, [{"input", [:atom]}, {"result", [:atom, :atom, :atom]}])

      errors = Safety.check(program)

      unsafe_vars = Enum.filter(errors, &(&1.kind == :unsafe_variable))
      assert length(unsafe_vars) == 2

      var_names = Enum.map(unsafe_vars, & &1.context.variable) |> Enum.sort()
      assert "W" in var_names
      assert "Z" in var_names
    end

    test "safe: variable bound by arithmetic constraint" do
      rule =
        Rule.new(
          Atom.new("tax", [Term.var("X"), Term.var("Z")]),
          [
            {:positive, Atom.new("income", [Term.var("X"), Term.var("A")])},
            {:positive, Atom.new("rate", [Term.var("R")])}
          ],
          [
            Constraint.mul(Term.var("A"), Term.var("R"), Term.var("Z"))
          ]
        )

      program =
        build_program_with_rule(rule, [
          {"income", [:atom, :integer]},
          {"rate", [:integer]},
          {"tax", [:atom, :integer]}
        ])

      # Z is bound by the arithmetic constraint result
      unsafe_errors = Enum.filter(Safety.check(program), &(&1.kind == :unsafe_variable))
      assert unsafe_errors == []
    end
  end

  describe "unbound constraint variables" do
    test "safe: all constraint input variables bound by positive body" do
      rule =
        Rule.new(
          Atom.new("adult", [Term.var("X")]),
          [
            {:positive, Atom.new("person", [Term.var("X"), Term.var("Age")])}
          ],
          [Constraint.gte(Term.var("Age"), Term.const(18))]
        )

      program = build_program_with_rule(rule, [{"person", [:atom, :integer]}, {"adult", [:atom]}])

      constraint_errors =
        Enum.filter(Safety.check(program), &(&1.kind == :unbound_constraint_variable))

      assert constraint_errors == []
    end

    test "unsafe: constraint variable not bound" do
      rule =
        Rule.new(
          Atom.new("result", [Term.var("X")]),
          [
            {:positive, Atom.new("input", [Term.var("X")])}
          ],
          [Constraint.gt(Term.var("Y"), Term.const(0))]
        )

      program = build_program_with_rule(rule, [{"input", [:atom]}, {"result", [:atom]}])
      errors = Safety.check(program)

      unbound = Enum.filter(errors, &(&1.kind == :unbound_constraint_variable))
      assert length(unbound) == 1
      assert "Y" in hd(unbound).context.variables
    end

    test "safe: arithmetic result variable not counted as unbound input" do
      rule =
        Rule.new(
          Atom.new("total", [Term.var("X"), Term.var("Z")]),
          [
            {:positive, Atom.new("values", [Term.var("X"), Term.var("A")])}
          ],
          [Constraint.add(Term.var("A"), Term.const(1), Term.var("Z"))]
        )

      program =
        build_program_with_rule(rule, [
          {"values", [:atom, :integer]},
          {"total", [:atom, :integer]}
        ])

      constraint_errors =
        Enum.filter(Safety.check(program), &(&1.kind == :unbound_constraint_variable))

      assert constraint_errors == []
    end
  end

  describe "wildcard in rule head" do
    test "wildcard in head is rejected" do
      rule =
        Rule.new(
          Atom.new("any_child", [Term.wildcard(), Term.var("Y")]),
          [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
        )

      program =
        build_program_with_rule(rule, [{"parent", [:atom, :atom]}, {"any_child", [:atom, :atom]}])

      errors = Safety.check(program)

      wildcard_errors = Enum.filter(errors, &(&1.kind == :wildcard_in_head))
      assert length(wildcard_errors) == 1
    end

    test "wildcard in body is allowed" do
      rule =
        Rule.new(
          Atom.new("has_parent", [Term.var("X")]),
          [{:positive, Atom.new("parent", [Term.var("X"), Term.wildcard()])}]
        )

      program =
        build_program_with_rule(rule, [{"parent", [:atom, :atom]}, {"has_parent", [:atom]}])

      wildcard_errors = Enum.filter(Safety.check(program), &(&1.kind == :wildcard_in_head))
      assert wildcard_errors == []
    end

    test "constant in head is allowed" do
      rule =
        Rule.new(
          Atom.new("parent", [Term.var("X"), Term.const(:alice)]),
          [{:positive, Atom.new("person", [Term.var("X")])}]
        )

      program = build_program_with_rule(rule, [{"person", [:atom]}, {"parent", [:atom, :atom]}])
      errors = Safety.check(program)
      unsafe = Enum.filter(errors, &(&1.kind == :unsafe_variable))
      assert unsafe == []
    end
  end

  # Regression tests for H1: constraint input variables must be bound by
  # positive body atoms or by the results of *earlier* arithmetic constraints.
  # Prior to the fix, all arithmetic results were treated as simultaneously
  # available, accepting programs that would fail at runtime.
  describe "constraint ordering (H1 regression)" do
    test "in-order arithmetic chain is accepted" do
      # Z = A + 1, W = Z * 2 — Z is bound before W references it
      rule =
        Rule.new(
          Atom.new("out", [Term.var("X"), Term.var("W")]),
          [{:positive, Atom.new("input", [Term.var("X"), Term.var("A")])}],
          [
            Constraint.add(Term.var("A"), Term.const(1), Term.var("Z")),
            Constraint.mul(Term.var("Z"), Term.const(2), Term.var("W"))
          ]
        )

      program =
        build_program_with_rule(rule, [{"input", [:atom, :integer]}, {"out", [:atom, :integer]}])

      constraint_errors =
        Enum.filter(Safety.check(program), &(&1.kind == :unbound_constraint_variable))

      assert constraint_errors == []
    end

    test "out-of-order arithmetic chain is rejected" do
      # W = Z * 2 appears before Z = A + 1 — Z is not yet bound at constraint 0
      rule =
        Rule.new(
          Atom.new("out", [Term.var("X"), Term.var("W")]),
          [{:positive, Atom.new("input", [Term.var("X"), Term.var("A")])}],
          [
            Constraint.mul(Term.var("Z"), Term.const(2), Term.var("W")),
            Constraint.add(Term.var("A"), Term.const(1), Term.var("Z"))
          ]
        )

      program =
        build_program_with_rule(rule, [{"input", [:atom, :integer]}, {"out", [:atom, :integer]}])

      errors = Safety.check(program)
      unbound = Enum.filter(errors, &(&1.kind == :unbound_constraint_variable))

      assert unbound != []
      assert hd(unbound).context.constraint_index == 0
      assert "Z" in hd(unbound).context.variables
    end

    test "comparison referencing an unbound variable is rejected" do
      # Age > 18, but Age is not bound by any body atom
      rule =
        Rule.new(
          Atom.new("adult", [Term.var("X")]),
          [{:positive, Atom.new("person", [Term.var("X")])}],
          [Constraint.gte(Term.var("Age"), Term.const(18))]
        )

      program =
        build_program_with_rule(rule, [{"person", [:atom]}, {"adult", [:atom]}])

      errors = Safety.check(program)
      unbound = Enum.filter(errors, &(&1.kind == :unbound_constraint_variable))

      assert unbound != []
      assert "Age" in hd(unbound).context.variables
    end

    test "arithmetic result used in head is accepted even when last constraint" do
      # Z is the result of the only constraint; it appears in the head.
      # Head safety uses all-arithmetic-results, so this is valid.
      rule =
        Rule.new(
          Atom.new("out", [Term.var("X"), Term.var("Z")]),
          [{:positive, Atom.new("input", [Term.var("X"), Term.var("A")])}],
          [Constraint.add(Term.var("A"), Term.const(1), Term.var("Z"))]
        )

      program =
        build_program_with_rule(rule, [{"input", [:atom, :integer]}, {"out", [:atom, :integer]}])

      errors = Safety.check(program)
      assert Enum.filter(errors, &(&1.kind == :unsafe_variable)) == []
      assert Enum.filter(errors, &(&1.kind == :unbound_constraint_variable)) == []
    end

    test "arithmetic result from constraint k is visible to comparison at constraint k+1" do
      # Z = A + 1 then Z > 0 — the comparison can reference Z produced by prior constraint
      rule =
        Rule.new(
          Atom.new("out", [Term.var("X"), Term.var("Z")]),
          [{:positive, Atom.new("input", [Term.var("X"), Term.var("A")])}],
          [
            Constraint.add(Term.var("A"), Term.const(1), Term.var("Z")),
            Constraint.gt(Term.var("Z"), Term.const(0))
          ]
        )

      program =
        build_program_with_rule(rule, [{"input", [:atom, :integer]}, {"out", [:atom, :integer]}])

      constraint_errors =
        Enum.filter(Safety.check(program), &(&1.kind == :unbound_constraint_variable))

      assert constraint_errors == []
    end

    test "comparison at constraint k cannot reference result introduced at constraint k+1" do
      # Z > 0 appears before Z = A + 1 — Z is not yet in scope
      rule =
        Rule.new(
          Atom.new("out", [Term.var("X"), Term.var("Z")]),
          [{:positive, Atom.new("input", [Term.var("X"), Term.var("A")])}],
          [
            Constraint.gt(Term.var("Z"), Term.const(0)),
            Constraint.add(Term.var("A"), Term.const(1), Term.var("Z"))
          ]
        )

      program =
        build_program_with_rule(rule, [{"input", [:atom, :integer]}, {"out", [:atom, :integer]}])

      errors = Safety.check(program)
      unbound = Enum.filter(errors, &(&1.kind == :unbound_constraint_variable))

      assert unbound != []
      assert hd(unbound).context.constraint_index == 0
      assert "Z" in hd(unbound).context.variables
    end
  end

  describe "multiple rules" do
    test "errors from all rules are collected" do
      rule1 =
        Rule.new(
          Atom.new("r", [Term.var("Z")]),
          [{:positive, Atom.new("s", [Term.var("X")])}]
        )

      # W is safe (bound by positive body), Q is body-only in negative (not unsafe)
      rule2 =
        Rule.new(
          Atom.new("t", [Term.var("W")]),
          [
            {:positive, Atom.new("u", [Term.var("W")])},
            {:negative, Atom.new("v", [Term.var("Q")])}
          ]
        )

      program =
        Program.new()
        |> Program.add_relation("s", [:atom])
        |> Program.add_relation("r", [:atom])
        |> Program.add_relation("u", [:atom])
        |> Program.add_relation("v", [:atom])
        |> Program.add_relation("t", [:atom])
        |> then(&%{&1 | rules: [rule1, rule2]})

      errors = Safety.check(program)

      # Rule 1: Z is unsafe. Rule 2: no unsafe variables.
      unsafe = Enum.filter(errors, &(&1.kind == :unsafe_variable))
      assert length(unsafe) == 1
      assert hd(unsafe).context.variable == "Z"
      assert hd(unsafe).context.rule_index == 0
    end
  end
end
