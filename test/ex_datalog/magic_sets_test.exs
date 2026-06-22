defmodule ExDatalog.MagicSetsTest do
  use ExUnit.Case, async: true

  alias ExDatalog.{Atom, Knowledge, MagicSets, Program, Rule, Term}

  defp ancestor_program(facts) do
    base =
      Program.new()
      |> Program.add_relation("parent", [:atom, :atom])
      |> Program.add_relation("ancestor", [:atom, :atom])

    base = Enum.reduce(facts, base, fn {p, c}, acc -> Program.add_fact(acc, "parent", [p, c]) end)

    base
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
  end

  @chain [{:a, :b}, {:b, :c}, {:c, :d}, {:d, :e}]

  describe "correctness vs semi-naive" do
    test "goal-restricted query matches the semi-naive subset" do
      program = ancestor_program(@chain)

      {:ok, full} = ExDatalog.materialize(program)
      full_ancestors = Knowledge.get(full, "ancestor")
      expected = MapSet.filter(full_ancestors, fn {x, _y} -> x == :a end)

      {:ok, magic} =
        ExDatalog.materialize(program, strategy: :magic_sets, goal: {"ancestor", [:a, :_]})

      result = Knowledge.match(magic, "ancestor", [:a, :_])
      assert result == expected
    end

    test "falls back to semi-naive when no goal is given" do
      program = ancestor_program(@chain)
      {:ok, magic} = ExDatalog.materialize(program, strategy: :magic_sets)
      {:ok, full} = ExDatalog.materialize(program)
      assert Knowledge.get(magic, "ancestor") == Knowledge.get(full, "ancestor")
    end

    test "falls back to semi-naive for an all-free goal" do
      program = ancestor_program(@chain)

      {:ok, magic} =
        ExDatalog.materialize(program, strategy: :magic_sets, goal: {"ancestor", [:_, :_]})

      {:ok, full} = ExDatalog.materialize(program)
      assert Knowledge.get(magic, "ancestor") == Knowledge.get(full, "ancestor")
    end
  end

  describe "transform/2 directly" do
    test "produces a magic relation, seed fact, and rewritten rules for a bound goal" do
      {:ok, ir} = ExDatalog.compile(ancestor_program(@chain))
      {:ok, transformed} = MagicSets.transform(ir, {"ancestor", [:a, :_]})

      magic = Enum.find(transformed.relations, fn r -> r.name == "magic_ancestor_bf" end)
      assert magic.arity == 1

      assert Enum.any?(transformed.facts, fn f ->
               f.relation == "magic_ancestor_bf" and f.values == [atom: :a]
             end)

      rewritten =
        Enum.filter(transformed.rules, fn r -> r.head.relation == "ancestor" end)

      assert Enum.all?(rewritten, fn r ->
               match?(
                 [{:positive, %ExDatalog.IR.Atom{relation: "magic_ancestor_bf"}} | _],
                 r.body
               )
             end)
    end

    test "returns :fallback for an all-free goal" do
      {:ok, ir} = ExDatalog.compile(ancestor_program(@chain))
      assert {:fallback, :no_bound_positions} = MagicSets.transform(ir, {"ancestor", [:_, :_]})
    end

    test "returns :fallback for a program containing aggregates" do
      program =
        Program.new()
        |> Program.add_relation("emp", [:atom, :atom])
        |> Program.add_relation("dept_count", [:atom, :integer])
        |> Program.add_fact("emp", [:alice, :eng])
        |> Program.add_rule(
          Rule.new(
            Atom.new("dept_count", [Term.var("D"), Term.var("N")]),
            [{:positive, Atom.new("emp", [Term.var("E"), Term.var("D")])}],
            [ExDatalog.Constraint.count(Term.var("E"), Term.var("N"))]
          )
        )

      {:ok, ir} = ExDatalog.compile(program)

      assert {:fallback, :unsupported_program} =
               MagicSets.transform(ir, {"dept_count", [:eng, :_]})
    end
  end

  describe "public API exercises magic-sets transform" do
    test "knowledge stats contain magic-prefixed relations when strategy is :magic_sets" do
      program = ancestor_program(@chain)

      {:ok, magic} =
        ExDatalog.materialize(program, strategy: :magic_sets, goal: {"ancestor", [:a, :_]})

      magic_rels =
        magic.stats.relation_sizes
        |> Map.keys()
        |> Enum.filter(&String.starts_with?(&1, "magic_"))

      assert magic_rels != [],
             "expected magic-prefixed relations in stats, got: #{inspect(magic.stats.relation_sizes)}"
    end

    test "knowledge stats have no magic-prefixed relations for plain semi-naive" do
      program = ancestor_program(@chain)

      {:ok, full} = ExDatalog.materialize(program)

      magic_rels =
        full.stats.relation_sizes
        |> Map.keys()
        |> Enum.filter(&String.starts_with?(&1, "magic_"))

      assert magic_rels == [],
             "expected no magic-prefixed relations in semi-naive stats, got: #{inspect(full.stats.relation_sizes)}"
    end

    test "magic-sets restricts ancestor derivation to goal-reachable nodes" do
      # Graph with two disconnected branches; goal queries only the first.
      facts = [
        {:a, :b},
        {:b, :c},
        {:c, :d},
        {:x, :y},
        {:y, :z}
      ]

      program = ancestor_program(facts)

      {:ok, magic} =
        ExDatalog.materialize(program, strategy: :magic_sets, goal: {"ancestor", [:a, :_]})

      {:ok, full} = ExDatalog.materialize(program)

      # Magic-sets ancestor table (before apply_goal filter) has only facts
      # reachable from :a, while semi-naive computes all branches.
      magic_ancestor = Knowledge.get(magic, "ancestor")
      full_ancestor = Knowledge.get(full, "ancestor")

      refute MapSet.member?(magic_ancestor, {:x, :y}),
             "magic-sets should not derive {:x, :y} (unrelated to goal :a)"

      assert MapSet.member?(full_ancestor, {:x, :y}),
             "semi-naive should derive {:x, :y}"

      assert MapSet.member?(magic_ancestor, {:a, :d}),
             "magic-sets should derive {:a, :d} (goal-reachable)"
    end
  end

  describe "unsupported programs fall back" do
    test "program with negation falls back to semi-naive" do
      program =
        Program.new()
        |> Program.add_relation("person", [:atom])
        |> Program.add_relation("parent", [:atom, :atom])
        |> Program.add_relation("childless", [:atom])
        |> Program.add_fact("person", [:alice])
        |> Program.add_fact("person", [:bob])
        |> Program.add_fact("parent", [:alice, :carol])
        |> Program.add_rule(
          Rule.new(
            Atom.new("childless", [Term.var("X")]),
            [
              {:positive, Atom.new("person", [Term.var("X")])},
              {:negative, Atom.new("parent", [Term.var("X"), :wildcard])}
            ]
          )
        )

      {:ok, magic} =
        ExDatalog.materialize(program, strategy: :magic_sets, goal: {"childless", [:_]})

      {:ok, full} = ExDatalog.materialize(program)
      assert Knowledge.get(magic, "childless") == Knowledge.get(full, "childless")
    end
  end
end
