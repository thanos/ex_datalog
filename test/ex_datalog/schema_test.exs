defmodule ExDatalog.SchemaTest do
  use ExUnit.Case, async: true

  alias ExDatalog.{Atom, Knowledge, Program, Rule, Term}

  describe "relation/2 macro" do
    test "declares a relation with typed fields" do
      defmodule RelTest1 do
        use ExDatalog.Schema

        relation :parent do
          field :parent_name, :atom
          field :child_name, :atom
        end
      end

      program = RelTest1.program()
      assert Map.has_key?(program.relations, "parent")
      assert program.relations["parent"] == %{arity: 2, types: [:atom, :atom]}
    end

    test "declares multiple relations" do
      defmodule RelTest2 do
        use ExDatalog.Schema

        relation :parent do
          field :p, :atom
          field :c, :atom
        end

        relation :ancestor do
          field :a, :atom
          field :d, :atom
        end
      end

      program = RelTest2.program()
      assert Map.has_key?(program.relations, "parent")
      assert Map.has_key?(program.relations, "ancestor")
    end

    test "supports :integer and :string field types" do
      defmodule RelTest3 do
        use ExDatalog.Schema

        relation :income do
          field :person, :atom
          field :amount, :integer
        end

        relation :label do
          field :node, :atom
          field :text, :string
        end
      end

      program = RelTest3.program()
      assert program.relations["income"].types == [:atom, :integer]
      assert program.relations["label"].types == [:atom, :string]
    end

    test "supports :any field type" do
      defmodule RelTest4 do
        use ExDatalog.Schema

        relation :payload do
          field :key, :atom
          field :value, :any
        end
      end

      program = RelTest4.program()
      assert program.relations["payload"].types == [:atom, :any]
    end
  end

  describe "fact/1 macro" do
    test "declares a single ground fact" do
      defmodule FactTest1 do
        use ExDatalog.Schema

        relation :parent do
          field :p, :atom
          field :c, :atom
        end

        fact parent(:alice, :bob)
      end

      program = FactTest1.program()
      assert length(program.facts) == 1
      assert {"parent", [:alice, :bob]} in program.facts
    end

    test "declares multiple facts" do
      defmodule FactTest2 do
        use ExDatalog.Schema

        relation :parent do
          field :p, :atom
          field :c, :atom
        end

        fact parent(:alice, :bob)
        fact parent(:bob, :carol)
      end

      program = FactTest2.program()
      facts = Enum.map(program.facts, fn {rel, vals} -> {rel, vals} end)
      assert length(facts) == 2
      assert {"parent", [:alice, :bob]} in facts
      assert {"parent", [:bob, :carol]} in facts
    end
  end

  describe "facts/2 macro" do
    test "declares bulk facts with row syntax" do
      defmodule FactsTest1 do
        use ExDatalog.Schema

        relation :parent do
          field :p, :atom
          field :c, :atom
        end

        facts :parent do
          row :alice, :bob
          row :bob, :carol
          row :carol, :dave
        end
      end

      program = FactsTest1.program()
      facts = Enum.map(program.facts, fn {rel, vals} -> {rel, vals} end)
      assert length(facts) == 3
      assert {"parent", [:alice, :bob]} in facts
      assert {"parent", [:bob, :carol]} in facts
      assert {"parent", [:carol, :dave]} in facts
    end
  end

  describe "rule/2 macro" do
    test "declares a simple positive rule" do
      defmodule RuleTest1 do
        use ExDatalog.Schema

        relation :parent do
          field :p, :atom
          field :c, :atom
        end

        relation :ancestor do
          field :a, :atom
          field :d, :atom
        end

        rule ancestor(X, Y) do
          parent(X, Y)
        end
      end

      program = RuleTest1.program()
      assert length(program.rules) == 1

      rule = hd(program.rules)
      assert rule.head.relation == "ancestor"
      assert rule.head.terms == [Term.var("X"), Term.var("Y")]
      assert length(rule.body) == 1

      {:positive, body_atom} = hd(rule.body)
      assert body_atom.relation == "parent"
      assert body_atom.terms == [Term.var("X"), Term.var("Y")]
    end

    test "declares a recursive rule" do
      defmodule RuleTest2 do
        use ExDatalog.Schema

        relation :parent do
          field :p, :atom
          field :c, :atom
        end

        relation :ancestor do
          field :a, :atom
          field :d, :atom
        end

        rule ancestor(X, Z) do
          parent(X, Y)
          ancestor(Y, Z)
        end
      end

      program = RuleTest2.program()
      rule = hd(program.rules)
      assert rule.head.terms == [Term.var("X"), Term.var("Z")]
      assert length(rule.body) == 2
    end

    test "declares a rule with negation using not_" do
      defmodule RuleTest3 do
        use ExDatalog.Schema

        relation :male do
          field :p, :atom
        end

        relation :married do
          field :p, :atom
          field :sp, :atom
        end

        relation :bachelor do
          field :p, :atom
        end

        rule bachelor(P) do
          male(P)
          not_ married(P, _)
        end
      end

      program = RuleTest3.program()
      rule = hd(program.rules)
      assert rule.head.relation == "bachelor"

      negated =
        Enum.find(rule.body, fn
          {:negative, _} -> true
          _ -> false
        end)

      assert negated != nil

      {:negative, neg_atom} = negated
      assert neg_atom.relation == "married"
      assert neg_atom.terms == [Term.var("P"), Term.from(:_)]
    end

    test "declares a rule with constraint" do
      defmodule RuleTest4 do
        use ExDatalog.Schema

        relation :income do
          field :person, :atom
          field :amount, :integer
        end

        relation :high_earner do
          field :person, :atom
        end

        rule high_earner(P) do
          income(P, S)
          gt(S, 100_000)
        end
      end

      program = RuleTest4.program()
      rule = hd(program.rules)
      assert rule.head.relation == "high_earner"
      assert length(rule.constraints) == 1

      constraint = hd(rule.constraints)
      assert constraint.op == :gt
    end

    test "rule body constants use lowercase vs uppercase convention" do
      defmodule RuleTest5 do
        use ExDatalog.Schema

        relation :edge do
          field :from, :atom
          field :to, :atom
        end

        relation :reachable do
          field :from, :atom
          field :to, :atom
        end

        rule reachable(:start, Y) do
          edge(:start, Y)
        end
      end

      program = RuleTest5.program()
      rule = hd(program.rules)

      assert rule.head.terms == [Term.from(:start), Term.var("Y")]
    end
  end

  describe "materialize/0,1 integration" do
    test "full transitive closure pipeline" do
      defmodule PipelineTest1 do
        use ExDatalog.Schema

        relation :parent do
          field :p, :atom
          field :c, :atom
        end

        relation :ancestor do
          field :a, :atom
          field :d, :atom
        end

        fact parent(:alice, :bob)
        fact parent(:bob, :carol)
        fact parent(:carol, :dave)

        rule ancestor(X, Y) do
          parent(X, Y)
        end

        rule ancestor(X, Z) do
          parent(X, Y)
          ancestor(Y, Z)
        end
      end

      {:ok, knowledge} = PipelineTest1.materialize()

      ancestor = Knowledge.get(knowledge, "ancestor")
      assert MapSet.size(ancestor) == 6
      assert {:alice, :bob} in ancestor
      assert {:alice, :carol} in ancestor
      assert {:alice, :dave} in ancestor
      assert {:bob, :carol} in ancestor
      assert {:bob, :dave} in ancestor
      assert {:carol, :dave} in ancestor
    end

    test "negation integration" do
      defmodule PipelineTest2 do
        use ExDatalog.Schema

        relation :male do
          field :p, :atom
        end

        relation :married do
          field :p, :atom
          field :sp, :atom
        end

        relation :bachelor do
          field :p, :atom
        end

        fact male(:bob)
        fact male(:tom)
        fact married(:tom, :sally)

        rule bachelor(P) do
          male(P)
          not_ married(P, _)
        end
      end

      {:ok, knowledge} = PipelineTest2.materialize()
      bachelor = Knowledge.get(knowledge, "bachelor")
      assert MapSet.size(bachelor) == 1
      assert {:bob} in bachelor
    end

    test "constraint integration" do
      defmodule PipelineTest3 do
        use ExDatalog.Schema

        relation :income do
          field :person, :atom
          field :amount, :integer
        end

        relation :high_earner do
          field :person, :atom
        end

        fact income(:alice, 150_000)
        fact income(:bob, 50_000)
        fact income(:carol, 200_000)

        rule high_earner(P) do
          income(P, S)
          gt(S, 100_000)
        end
      end

      {:ok, knowledge} = PipelineTest3.materialize()
      high_earner = Knowledge.get(knowledge, "high_earner")
      assert MapSet.size(high_earner) == 2
      assert {:alice} in high_earner
      assert {:carol} in high_earner
    end

    test "facts macro bulk insertion" do
      defmodule PipelineTest4 do
        use ExDatalog.Schema

        relation :edge do
          field :from, :atom
          field :to, :atom
        end

        relation :path do
          field :from, :atom
          field :to, :atom
        end

        facts :edge do
          row :a, :b
          row :b, :c
          row :c, :d
        end

        rule path(X, Y) do
          edge(X, Y)
        end
      end

      {:ok, knowledge} = PipelineTest4.materialize()
      path = Knowledge.get(knowledge, "path")
      assert MapSet.size(path) == 3
    end
  end

  describe "query/2 macro" do
    test "named query against materialized knowledge" do
      defmodule QueryTest1 do
        use ExDatalog.Schema

        relation :parent do
          field :p, :atom
          field :c, :atom
        end

        relation :ancestor do
          field :a, :atom
          field :d, :atom
        end

        fact parent(:alice, :bob)
        fact parent(:bob, :carol)

        rule ancestor(X, Y) do
          parent(X, Y)
        end

        query :all_ancestors do
          find X, Y
          where ancestor(X, Y)
        end
      end

      {:ok, knowledge} = QueryTest1.materialize()
      results = QueryTest1.query(:all_ancestors, knowledge)
      assert length(results) == 2
      assert {:alice, :bob} in results
      assert {:bob, :carol} in results
    end

    test "query with constant pattern" do
      defmodule QueryTest2 do
        use ExDatalog.Schema

        relation :parent do
          field :p, :atom
          field :c, :atom
        end

        relation :ancestor do
          field :a, :atom
          field :d, :atom
        end

        fact parent(:alice, :bob)
        fact parent(:bob, :carol)

        rule ancestor(X, Y) do
          parent(X, Y)
        end

        query :descendants_of_alice do
          find Y
          where ancestor(:alice, Y)
        end
      end

      {:ok, knowledge} = QueryTest2.materialize()
      results = QueryTest2.query(:descendants_of_alice, knowledge)
      assert :bob in results
    end

    test "query raises on unknown name" do
      defmodule QueryTest3 do
        use ExDatalog.Schema

        relation :parent do
          field :p, :atom
          field :c, :atom
        end

        fact parent(:alice, :bob)

        query :known_query do
          find X
          where parent(X, _)
        end
      end

      {:ok, knowledge} = QueryTest3.materialize()

      assert_raise ArgumentError, ~r/unknown query/, fn ->
        QueryTest3.query(:nonexistent, knowledge)
      end
    end
  end

  describe "queries/0" do
    test "returns query metadata" do
      defmodule QueriesTest do
        use ExDatalog.Schema

        relation :parent do
          field :p, :atom
          field :c, :atom
        end

        fact parent(:alice, :bob)

        query :kids_of_alice do
          find C
          where parent(:alice, C)
        end
      end

      queries = QueriesTest.queries()
      assert Map.has_key?(queries, :kids_of_alice)
      assert queries.kids_of_alice.relation == "parent"
    end
  end

  describe "backward compatibility" do
    test "DSL program is compatible with builder API" do
      defmodule CompatTest do
        use ExDatalog.Schema

        relation :parent do
          field :p, :atom
          field :c, :atom
        end

        relation :ancestor do
          field :a, :atom
          field :d, :atom
        end

        fact parent(:alice, :bob)
      end

      program = CompatTest.program()

      extended =
        program
        |> Program.add_fact("parent", [:bob, :carol])
        |> Program.add_rule(
          Rule.new(
            Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
            [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
          )
        )

      {:ok, knowledge} = ExDatalog.materialize(extended)
      ancestor = Knowledge.get(knowledge, "ancestor")
      assert MapSet.size(ancestor) == 2
    end
  end

  describe "arithmetic constraint in DSL" do
    test "add constraint" do
      defmodule ArithTest do
        use ExDatalog.Schema

        relation :salary do
          field :person, :atom
          field :base, :integer
        end

        relation :total_comp do
          field :person, :atom
          field :total, :integer
        end

        fact salary(:alice, 100)
        fact salary(:bob, 80)

        rule total_comp(P, T) do
          salary(P, B)
          add(B, 20, T)
        end
      end

      {:ok, knowledge} = ArithTest.materialize()
      total = Knowledge.get(knowledge, "total_comp")
      assert MapSet.size(total) == 2
      assert {:alice, 120} in total
      assert {:bob, 100} in total
    end
  end

  describe "UnsupportedFeature" do
    test "aggregate spike returns UnsupportedFeature struct" do
      assert %ExDatalog.UnsupportedFeature{feature: :aggregates, planned_for: "v0.6.0"}.feature == :aggregates
    end
  end
end
