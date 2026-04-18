defmodule ExDatalog.Compiler.StratifierTest do
  use ExUnit.Case, async: true

  alias ExDatalog.{Atom, Compiler.Stratifier, Program, Rule, Term}

  defp build_program_with_rules(rules, relations) do
    program =
      Enum.reduce(relations, Program.new(), fn {name, types}, acc ->
        Program.add_relation(acc, name, types)
      end)

    %{program | rules: rules}
  end

  describe "assign/1" do
    test "single positive rule gets stratum 0" do
      rule =
        Rule.new(
          Atom.new("path", [Term.var("X"), Term.var("Y")]),
          [{:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}]
        )

      program =
        build_program_with_rules([rule], [{"edge", [:atom, :atom]}, {"path", [:atom, :atom]}])

      strata = Stratifier.assign(program)

      assert strata[0] == 0
    end

    test "negation across strata assigns higher stratum" do
      rule =
        Rule.new(
          Atom.new("bachelor", [Term.var("X")]),
          [
            {:positive, Atom.new("male", [Term.var("X")])},
            {:negative, Atom.new("married", [Term.var("X"), Term.wildcard()])}
          ]
        )

      program =
        build_program_with_rules([rule], [
          {"male", [:atom]},
          {"married", [:atom, :atom]},
          {"bachelor", [:atom]}
        ])

      strata = Stratifier.assign(program)

      assert strata[0] >= 1
    end

    test "recursive positive rule gets stratum 0" do
      rule1 =
        Rule.new(Atom.new("path", [Term.var("X"), Term.var("Y")]), [
          {:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}
        ])

      rule2 =
        Rule.new(Atom.new("path", [Term.var("X"), Term.var("Z")]), [
          {:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])},
          {:positive, Atom.new("path", [Term.var("Y"), Term.var("Z")])}
        ])

      program =
        build_program_with_rules([rule1, rule2], [
          {"edge", [:atom, :atom]},
          {"path", [:atom, :atom]}
        ])

      strata = Stratifier.assign(program)

      assert strata[0] == 0
      assert strata[1] == 0
    end
  end

  describe "compute_strata/1" do
    test "single-stratum program has one stratum" do
      rule =
        Rule.new(
          Atom.new("path", [Term.var("X"), Term.var("Y")]),
          [{:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}]
        )

      program =
        build_program_with_rules([rule], [{"edge", [:atom, :atom]}, {"path", [:atom, :atom]}])

      strata = Stratifier.compute_strata(program)

      assert length(strata) == 1
      assert hd(strata).index == 0
    end

    test "multi-stratum program has correct number of strata" do
      rule =
        Rule.new(
          Atom.new("bachelor", [Term.var("X")]),
          [
            {:positive, Atom.new("male", [Term.var("X")])},
            {:negative, Atom.new("married", [Term.var("X"), Term.wildcard()])}
          ]
        )

      program =
        build_program_with_rules([rule], [
          {"male", [:atom]},
          {"married", [:atom, :atom]},
          {"bachelor", [:atom]}
        ])

      strata = Stratifier.compute_strata(program)

      max_stratum = strata |> Enum.map(& &1.index) |> Enum.max()
      assert max_stratum >= 1
    end

    test "strata are ordered by index" do
      rule =
        Rule.new(
          Atom.new("bachelor", [Term.var("X")]),
          [
            {:positive, Atom.new("male", [Term.var("X")])},
            {:negative, Atom.new("married", [Term.var("X"), Term.wildcard()])}
          ]
        )

      program =
        build_program_with_rules([rule], [
          {"male", [:atom]},
          {"married", [:atom, :atom]},
          {"bachelor", [:atom]}
        ])

      strata = Stratifier.compute_strata(program)
      indices = Enum.map(strata, & &1.index)

      assert indices == Enum.sort(indices)
    end

    test "stratum contains correct rule_ids for its rules" do
      rule =
        Rule.new(
          Atom.new("path", [Term.var("X"), Term.var("Y")]),
          [{:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}]
        )

      program =
        build_program_with_rules([rule], [{"edge", [:atom, :atom]}, {"path", [:atom, :atom]}])

      strata = Stratifier.compute_strata(program)
      stratum = Enum.find(strata, &(&1.index == 0))

      assert 0 in stratum.rule_ids
      assert "path" in stratum.relations
    end
  end
end
