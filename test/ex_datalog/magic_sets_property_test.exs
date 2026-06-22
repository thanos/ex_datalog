defmodule ExDatalog.MagicSetsPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExDatalog.{Atom, Knowledge, Program, Rule, Term}

  @nodes [:a, :b, :c, :d, :e, :f]

  defp edge_gen do
    gen all(from <- member_of(@nodes), to <- member_of(@nodes)) do
      {from, to}
    end
  end

  defp build_program(edges) do
    base =
      Program.new()
      |> Program.add_relation("edge", [:atom, :atom])
      |> Program.add_relation("path", [:atom, :atom])

    base = Enum.reduce(edges, base, fn {f, t}, acc -> Program.add_fact(acc, "edge", [f, t]) end)

    base
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
  end

  property "magic-sets result equals the semi-naive subset for the goal" do
    check all(
            edges <- list_of(edge_gen(), max_length: 10),
            source <- member_of(@nodes)
          ) do
      program = build_program(edges)

      {:ok, full} = ExDatalog.materialize(program)
      expected = MapSet.filter(Knowledge.get(full, "path"), fn {x, _y} -> x == source end)

      {:ok, magic} =
        ExDatalog.materialize(program, strategy: :magic_sets, goal: {"path", [source, :_]})

      actual = Knowledge.match(magic, "path", [source, :_])

      assert actual == expected
    end
  end
end
