defmodule ExDatalog.Integration.PortabilityTest do
  @moduledoc """
  Portability tests: the same program must produce identical results
  regardless of which storage backend is used.

  These tests evaluate a variety of Datalog programs with both the Map
  and ETS backends and assert that the derived relations are identical.
  """
  use ExUnit.Case, async: false

  alias ExDatalog.{Atom, Constraint, Program, Rule, Term}
  alias ExDatalog.Engine.Naive

  defp parent_ancestor_program do
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
  end

  defp arithmetic_program do
    Program.new()
    |> Program.add_relation("number", [:integer])
    |> Program.add_relation("doubled", [:integer, :integer])
    |> Program.add_fact("number", [1])
    |> Program.add_fact("number", [2])
    |> Program.add_fact("number", [3])
    |> Program.add_rule(
      Rule.new(
        Atom.new("doubled", [Term.var("X"), Term.var("Y")]),
        [{:positive, Atom.new("number", [Term.var("X")])}],
        [Constraint.add(Term.var("X"), {:const, 2}, Term.var("Y"))]
      )
    )
  end

  defp comparison_program do
    Program.new()
    |> Program.add_relation("number", [:integer])
    |> Program.add_relation("big", [:integer])
    |> Program.add_fact("number", [1])
    |> Program.add_fact("number", [5])
    |> Program.add_fact("number", [10])
    |> Program.add_fact("number", [3])
    |> Program.add_rule(
      Rule.new(
        Atom.new("big", [Term.var("X")]),
        [{:positive, Atom.new("number", [Term.var("X")])}],
        [Constraint.gt(Term.var("X"), {:const, 4})]
      )
    )
  end

  defp negation_program do
    Program.new()
    |> Program.add_relation("person", [:atom])
    |> Program.add_relation("parent", [:atom, :atom])
    |> Program.add_relation("childless", [:atom])
    |> Program.add_fact("person", [:alice])
    |> Program.add_fact("person", [:bob])
    |> Program.add_fact("person", [:carol])
    |> Program.add_fact("parent", [:alice, :dave])
    |> Program.add_fact("parent", [:carol, :eve])
    |> Program.add_rule(
      Rule.new(
        Atom.new("childless", [Term.var("X")]),
        [
          {:positive, Atom.new("person", [Term.var("X")])},
          {:negative, Atom.new("parent", [Term.var("X"), Term.var("Y")])}
        ]
      )
    )
  end

  defp shared_first_element_program do
    Program.new()
    |> Program.add_relation("parent", [:atom, :atom])
    |> Program.add_fact("parent", [:alice, :bob])
    |> Program.add_fact("parent", [:alice, :carol])
    |> Program.add_fact("parent", [:alice, :dave])
    |> Program.add_fact("parent", [:bob, :eve])
  end

  defp evaluate_with_both_backends(program) do
    {:ok, ir} =
      program
      |> ExDatalog.validate()
      |> then(fn
        {:ok, p} -> ExDatalog.compile(p)
        {:error, _} = err -> err
      end)

    {:ok, map_result} = Naive.evaluate(ir, storage: ExDatalog.Storage.Map)
    {:ok, ets_result} = Naive.evaluate(ir, storage: ExDatalog.Storage.ETS)

    {map_result, ets_result}
  end

  defp same_relations?(map_result, ets_result) do
    map_rels = MapSet.new(Map.keys(map_result.relations))
    ets_rels = MapSet.new(Map.keys(ets_result.relations))

    if map_rels != ets_rels do
      {:mismatch, {:map_relations, MapSet.to_list(map_rels)},
       {:ets_relations, MapSet.to_list(ets_rels)}}
    else
      all_rels_match?(map_result, ets_result)
    end
  end

  defp all_rels_match?(map_result, ets_result) do
    Enum.reduce_while(Map.keys(map_result.relations), :ok, fn rel, _acc ->
      map_tuples = sorted_tuples(map_result, rel)
      ets_tuples = sorted_tuples(ets_result, rel)

      if map_tuples == ets_tuples do
        {:cont, :ok}
      else
        {:halt, {:mismatch, rel, {:map, map_tuples}, {:ets, ets_tuples}}}
      end
    end)
  end

  defp sorted_tuples(result, rel) do
    result.relations[rel] |> MapSet.to_list() |> Enum.sort()
  end

  describe "portability: Map vs ETS" do
    test "transitive closure produces identical results" do
      {map_result, ets_result} = evaluate_with_both_backends(parent_ancestor_program())
      assert :ok == same_relations?(map_result, ets_result)
    end

    test "arithmetic constraints produce identical results" do
      {map_result, ets_result} = evaluate_with_both_backends(arithmetic_program())
      assert :ok == same_relations?(map_result, ets_result)
    end

    test "comparison constraints produce identical results" do
      {map_result, ets_result} = evaluate_with_both_backends(comparison_program())
      assert :ok == same_relations?(map_result, ets_result)
    end

    test "negation produces identical results" do
      {map_result, ets_result} = evaluate_with_both_backends(negation_program())
      assert :ok == same_relations?(map_result, ets_result)
    end

    test "shared first element (multi-arity key collision) produces identical results" do
      {map_result, ets_result} = evaluate_with_both_backends(shared_first_element_program())
      assert :ok == same_relations?(map_result, ets_result)
    end

    test "stats match between backends" do
      {map_result, ets_result} = evaluate_with_both_backends(parent_ancestor_program())
      assert map_result.stats.iterations == ets_result.stats.iterations
      assert map_result.stats.relation_sizes == ets_result.stats.relation_sizes
    end
  end
end
