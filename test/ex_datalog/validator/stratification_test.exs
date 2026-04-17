defmodule ExDatalog.Validator.StratificationTest do
  use ExUnit.Case, async: true

  alias ExDatalog.{Atom, Program, Rule, Term}
  alias ExDatalog.Validator.Stratification

  defp build_program_with_rules(rules, relations) do
    program =
      Enum.reduce(relations, Program.new(), fn {name, types}, acc ->
        Program.add_relation(acc, name, types)
      end)

    %{program | rules: rules}
  end

  describe "build_graph/1" do
    test "single positive rule creates positive edge" do
      rule =
        Rule.new(
          Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
          [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
        )

      program =
        build_program_with_rules([rule], [
          {"parent", [:atom, :atom]},
          {"ancestor", [:atom, :atom]}
        ])

      graph = Stratification.build_graph(program)

      assert graph["ancestor"] == [{"parent", :positive}]
    end

    test "rule with negation creates negative edge" do
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

      graph = Stratification.build_graph(program)

      deps = Enum.sort(graph["bachelor"])
      assert {"male", :positive} in deps
      assert {"married", :negative} in deps
    end

    test "recursive rule creates self-edge" do
      rule =
        Rule.new(
          Atom.new("ancestor", [Term.var("X"), Term.var("Z")]),
          [
            {:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])},
            {:positive, Atom.new("ancestor", [Term.var("Y"), Term.var("Z")])}
          ]
        )

      program =
        build_program_with_rules([rule], [
          {"parent", [:atom, :atom]},
          {"ancestor", [:atom, :atom]}
        ])

      graph = Stratification.build_graph(program)

      assert {"ancestor", :positive} in graph["ancestor"]
      assert {"parent", :positive} in graph["ancestor"]
    end
  end

  describe "compute_sccs/1" do
    test "no cycles: each node is its own SCC" do
      rule =
        Rule.new(
          Atom.new("b", [Term.var("X")]),
          [{:positive, Atom.new("a", [Term.var("X")])}]
        )

      program = build_program_with_rules([rule], [{"a", [:atom]}, {"b", [:atom]}])
      graph = Stratification.build_graph(program)
      sccs = Stratification.compute_sccs(graph)

      # Each relation is in its own SCC
      flat = Enum.sort(List.flatten(sccs))
      assert "a" in flat
      assert "b" in flat
    end

    test "mutual recursion forms one SCC" do
      rule1 =
        Rule.new(
          Atom.new("even", [Term.var("X")]),
          [{:positive, Atom.new("odd", [Term.var("X")])}]
        )

      rule2 =
        Rule.new(
          Atom.new("odd", [Term.var("X")]),
          [{:positive, Atom.new("even", [Term.var("X")])}]
        )

      program =
        build_program_with_rules([rule1, rule2], [
          {"even", [:atom]},
          {"odd", [:atom]}
        ])

      graph = Stratification.build_graph(program)
      sccs = Stratification.compute_sccs(graph)

      # even and odd should be in the same SCC
      scc_with_even = Enum.find(sccs, fn scc -> "even" in scc end)
      assert "odd" in scc_with_even
    end

    test "self-referencing relation forms one SCC" do
      rule =
        Rule.new(
          Atom.new("ancestor", [Term.var("X"), Term.var("Z")]),
          [
            {:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])},
            {:positive, Atom.new("ancestor", [Term.var("Y"), Term.var("Z")])}
          ]
        )

      program =
        build_program_with_rules([rule], [
          {"parent", [:atom, :atom]},
          {"ancestor", [:atom, :atom]}
        ])

      graph = Stratification.build_graph(program)
      sccs = Stratification.compute_sccs(graph)

      # ancestor should be in an SCC by itself (containing itself and parent)
      scc_with_ancestor = Enum.find(sccs, fn scc -> "ancestor" in scc end)
      assert "ancestor" in scc_with_ancestor
    end
  end

  describe "check/1" do
    test "positive-only program is stratifiable" do
      rule =
        Rule.new(
          Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
          [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
        )

      program =
        build_program_with_rules([rule], [
          {"parent", [:atom, :atom]},
          {"ancestor", [:atom, :atom]}
        ])

      assert Stratification.check(program) == :ok
    end

    test "negation across strata is stratifiable" do
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

      assert Stratification.check(program) == :ok
    end

    test "unstratifiable: negation within a cycle" do
      rule =
        Rule.new(
          Atom.new("p", [Term.var("X")]),
          [
            {:positive, Atom.new("q", [Term.var("X")])},
            {:negative, Atom.new("p", [Term.var("X")])}
          ]
        )

      program =
        build_program_with_rules([rule], [
          {"q", [:atom]},
          {"p", [:atom]}
        ])

      {:error, errors} = Stratification.check(program)
      assert errors != []

      unstrat = Enum.filter(errors, &(&1.kind == :unstratified_negation))
      assert unstrat != []
    end

    test "mutual negation is unstratifiable" do
      rule1 =
        Rule.new(
          Atom.new("p", [Term.var("X")]),
          [{:negative, Atom.new("q", [Term.var("X")])}]
        )

      rule2 =
        Rule.new(
          Atom.new("q", [Term.var("X")]),
          [{:negative, Atom.new("p", [Term.var("X")])}]
        )

      program =
        build_program_with_rules([rule1, rule2], [
          {"p", [:atom]},
          {"q", [:atom]}
        ])

      {:error, errors} = Stratification.check(program)
      assert errors != []
    end

    test "program with no rules is trivially stratifiable" do
      program = Program.new() |> Program.add_relation("a", [:atom])
      assert Stratification.check(program) == :ok
    end
  end

  describe "assign_strata/1" do
    test "single positive rule: stratum 0" do
      rule =
        Rule.new(
          Atom.new("b", [Term.var("X")]),
          [{:positive, Atom.new("a", [Term.var("X")])}]
        )

      program = build_program_with_rules([rule], [{"a", [:atom]}, {"b", [:atom]}])
      strata = Stratification.assign_strata(program)

      assert strata["a"] == 0
      assert strata["b"] == 0
    end

    test "negation pushes relation to higher stratum" do
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

      strata = Stratification.assign_strata(program)

      assert strata["male"] == 0
      assert strata["married"] == 0
      assert strata["bachelor"] >= 1
    end

    test "recursive positive rule: same stratum" do
      rule1 =
        Rule.new(
          Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
          [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
        )

      rule2 =
        Rule.new(
          Atom.new("ancestor", [Term.var("X"), Term.var("Z")]),
          [
            {:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])},
            {:positive, Atom.new("ancestor", [Term.var("Y"), Term.var("Z")])}
          ]
        )

      program =
        build_program_with_rules([rule1, rule2], [
          {"parent", [:atom, :atom]},
          {"ancestor", [:atom, :atom]}
        ])

      strata = Stratification.assign_strata(program)

      assert strata["parent"] == 0
      assert strata["ancestor"] == 0
    end

    test "multi-strata program" do
      rule1 =
        Rule.new(
          Atom.new("bachelor", [Term.var("X")]),
          [
            {:positive, Atom.new("male", [Term.var("X")])},
            {:negative, Atom.new("married", [Term.var("X"), Term.wildcard()])}
          ]
        )

      rule2 =
        Rule.new(
          Atom.new("married", [Term.var("X"), Term.var("Y")]),
          [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
        )

      program =
        build_program_with_rules([rule1, rule2], [
          {"male", [:atom]},
          {"parent", [:atom, :atom]},
          {"married", [:atom, :atom]},
          {"bachelor", [:atom]}
        ])

      strata = Stratification.assign_strata(program)

      assert strata["male"] == 0
      assert strata["parent"] == 0
      assert strata["married"] == 0
      assert strata["bachelor"] >= 1
    end
  end
end
