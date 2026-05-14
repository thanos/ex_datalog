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

  defp type_predicate_program do
    Program.new()
    |> Program.add_relation("value", [:integer])
    |> Program.add_relation("int_value", [:integer])
    |> Program.add_fact("value", [1])
    |> Program.add_fact("value", [2])
    |> Program.add_fact("value", [3])
    |> Program.add_fact("value", [:not_a_number])
    |> Program.add_rule(
      Rule.new(
        Atom.new("int_value", [Term.var("X")]),
        [{:positive, Atom.new("value", [Term.var("X")])}],
        [Constraint.type_integer(Term.var("X"))]
      )
    )
  end

  defp string_predicate_program do
    Program.new()
    |> Program.add_relation("word", [:atom])
    |> Program.add_relation("hello_word", [:atom])
    |> Program.add_fact("word", [:hello_world])
    |> Program.add_fact("word", [:goodbye])
    |> Program.add_fact("word", [:helsinki])
    |> Program.add_rule(
      Rule.new(
        Atom.new("hello_word", [Term.var("X")]),
        [{:positive, Atom.new("word", [Term.var("X")])}],
        [Constraint.type_atom(Term.var("X"))]
      )
    )
  end

  defp membership_program do
    Program.new()
    |> Program.add_relation("color", [:atom])
    |> Program.add_relation("primary_color", [:atom])
    |> Program.add_fact("color", [:red])
    |> Program.add_fact("color", [:blue])
    |> Program.add_fact("color", [:green])
    |> Program.add_fact("color", [:yellow])
    |> Program.add_rule(
      Rule.new(
        Atom.new("primary_color", [Term.var("X")]),
        [{:positive, Atom.new("color", [Term.var("X")])}],
        [Constraint.member(Term.var("X"), {:const, [:red, :blue, :green]})]
      )
    )
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

    test "stats match between backends for all programs" do
      programs = [
        {"parent_ancestor", parent_ancestor_program()},
        {"arithmetic", arithmetic_program()},
        {"comparison", comparison_program()},
        {"negation", negation_program()},
        {"shared_first_element", shared_first_element_program()},
        {"type_predicate", type_predicate_program()},
        {"string_predicate", string_predicate_program()},
        {"membership", membership_program()}
      ]

      for {name, program} <- programs do
        {map_result, ets_result} = evaluate_with_both_backends(program)

        assert map_result.stats.iterations == ets_result.stats.iterations,
               "iterations mismatch for #{name}: map=#{map_result.stats.iterations}, ets=#{ets_result.stats.iterations}"

        assert map_result.stats.relation_sizes == ets_result.stats.relation_sizes,
               "relation_sizes mismatch for #{name}"
      end
    end

    test "type predicates produce identical results across backends" do
      {map_result, ets_result} = evaluate_with_both_backends(type_predicate_program())
      assert :ok == same_relations?(map_result, ets_result)
    end

    test "string/type_atom predicates produce identical results across backends" do
      {map_result, ets_result} = evaluate_with_both_backends(string_predicate_program())
      assert :ok == same_relations?(map_result, ets_result)
    end

    test "membership constraint produces identical results across backends" do
      {map_result, ets_result} = evaluate_with_both_backends(membership_program())
      assert :ok == same_relations?(map_result, ets_result)
    end
  end
end
