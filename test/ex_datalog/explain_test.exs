defmodule ExDatalog.ExplainTest do
  use ExUnit.Case, async: true

  alias ExDatalog.{Atom, Explain, Program, Result, Rule, Term}

  describe "explain/3 with no provenance" do
    test "returns error when provenance is nil" do
      result = %Result{
        relations: %{"parent" => MapSet.new([{:alice, :bob}])},
        stats: %{iterations: 1, duration_us: 0, relation_sizes: %{"parent" => 1}},
        provenance: nil
      }

      assert {:error, :no_provenance} = Explain.explain(result, "parent", {:alice, :bob})
    end
  end

  describe "explain/3 with provenance" do
    test "base fact returns :base_fact" do
      {:ok, result} =
        Program.new()
        |> Program.add_relation("parent", [:atom, :atom])
        |> Program.add_fact("parent", [:alice, :bob])
        |> ExDatalog.query(explain: true)

      assert {:ok, :base_fact} = Explain.explain(result, "parent", {:alice, :bob})
    end

    test "single-rule derivation returns node with rule_id" do
      {:ok, result} =
        Program.new()
        |> Program.add_relation("parent", [:atom, :atom])
        |> Program.add_relation("ancestor", [:atom, :atom])
        |> Program.add_fact("parent", [:alice, :bob])
        |> Program.add_rule(
          Rule.new(
            Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
            [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
          )
        )
        |> ExDatalog.query(explain: true)

      assert {:ok, tree} = Explain.explain(result, "ancestor", {:alice, :bob})
      assert %Explain.Node{} = tree
      assert tree.fact == {:alice, :bob}
      assert tree.rule_id == 0
      assert :base_fact in tree.children
    end

    test "transitive closure derivation traces through multiple rules" do
      {:ok, result} =
        Program.new()
        |> Program.add_relation("parent", [:atom, :atom])
        |> Program.add_relation("ancestor", [:atom, :atom])
        |> Program.add_fact("parent", [:alice, :bob])
        |> Program.add_fact("parent", [:bob, :carol])
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
        |> ExDatalog.query(explain: true)

      # Direct derivation: parent -> ancestor
      # The direct rule (single body atom) derives ancestor(alice, bob)
      assert {:ok, tree} = Explain.explain(result, "ancestor", {:alice, :bob})
      assert %Explain.Node{} = tree
      direct_rule = result.provenance.rules[tree.rule_id]
      assert length(direct_rule.body) == 1

      # Transitive derivation: parent + ancestor -> ancestor
      # The transitive rule (two body atoms) derives ancestor(alice, carol)
      assert {:ok, tree} = Explain.explain(result, "ancestor", {:alice, :carol})
      assert %Explain.Node{} = tree
      assert tree.fact == {:alice, :carol}
      trans_rule = result.provenance.rules[tree.rule_id]
      assert length(trans_rule.body) == 2
      assert length(tree.children) >= 2
    end

    test "returns error for non-existent fact" do
      {:ok, result} =
        Program.new()
        |> Program.add_relation("parent", [:atom, :atom])
        |> Program.add_fact("parent", [:alice, :bob])
        |> ExDatalog.query(explain: true)

      assert {:error, :not_found} = Explain.explain(result, "parent", {:charlie, :dave})
    end

    test "negation derivation shows rule_id" do
      {:ok, result} =
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
        |> ExDatalog.query(explain: true)

      assert {:ok, tree} = Explain.explain(result, "bachelor", {:bob})
      assert tree.rule_id == 0
      assert tree.fact == {:bob}
    end

    test "fact-only program has provenance with :base attribution" do
      {:ok, result} =
        Program.new()
        |> Program.add_relation("person", [:atom])
        |> Program.add_fact("person", [:alice])
        |> Program.add_fact("person", [:bob])
        |> ExDatalog.query(explain: true)

      assert result.provenance != nil
      origins = result.provenance.fact_origins
      assert origins["person"][{:alice}] == :base
      assert origins["person"][{:bob}] == :base
    end

    test "provenance tracks rule derivation" do
      {:ok, result} =
        Program.new()
        |> Program.add_relation("edge", [:atom, :atom])
        |> Program.add_relation("path", [:atom, :atom])
        |> Program.add_fact("edge", [:a, :b])
        |> Program.add_rule(
          Rule.new(
            Atom.new("path", [Term.var("X"), Term.var("Y")]),
            [{:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}]
          )
        )
        |> ExDatalog.query(explain: true)

      origins = result.provenance.fact_origins
      assert origins["edge"][{:a, :b}] == :base
      assert origins["path"][{:a, :b}] == 0
    end
  end
end
