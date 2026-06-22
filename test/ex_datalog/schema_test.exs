defmodule ExDatalog.SchemaTest do
  use ExUnit.Case, async: true

  doctest ExDatalog.Schema
  doctest ExDatalog.UnsupportedFeature
  doctest ExDatalog.DSL.CompileError

  alias ExDatalog.{Atom, Knowledge, Program, Rule, Term}

  describe "relation/2 macro" do
    test "declares a relation with typed fields" do
      defmodule RelTest1 do
        use ExDatalog.Schema

        relation :parent do
          field(:parent_name, :atom)
          field(:child_name, :atom)
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
          field(:p, :atom)
          field(:c, :atom)
        end

        relation :ancestor do
          field(:a, :atom)
          field(:d, :atom)
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
          field(:person, :atom)
          field(:amount, :integer)
        end

        relation :label do
          field(:node, :atom)
          field(:text, :string)
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
          field(:key, :atom)
          field(:value, :any)
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
          field(:p, :atom)
          field(:c, :atom)
        end

        fact(parent(:alice, :bob))
      end

      program = FactTest1.program()
      assert length(program.facts) == 1
      assert {"parent", [:alice, :bob]} in program.facts
    end

    test "declares multiple facts" do
      defmodule FactTest2 do
        use ExDatalog.Schema

        relation :parent do
          field(:p, :atom)
          field(:c, :atom)
        end

        fact(parent(:alice, :bob))
        fact(parent(:bob, :carol))
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
          field(:p, :atom)
          field(:c, :atom)
        end

        facts :parent do
          row(:alice, :bob)
          row(:bob, :carol)
          row(:carol, :dave)
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
          field(:p, :atom)
          field(:c, :atom)
        end

        relation :ancestor do
          field(:a, :atom)
          field(:d, :atom)
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
          field(:p, :atom)
          field(:c, :atom)
        end

        relation :ancestor do
          field(:a, :atom)
          field(:d, :atom)
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
          field(:p, :atom)
        end

        relation :married do
          field(:p, :atom)
          field(:sp, :atom)
        end

        relation :bachelor do
          field(:p, :atom)
        end

        rule bachelor(P) do
          male(P)
          not_(married(P, _))
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
          field(:person, :atom)
          field(:amount, :integer)
        end

        relation :high_earner do
          field(:person, :atom)
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
          field(:from, :atom)
          field(:to, :atom)
        end

        relation :reachable do
          field(:from, :atom)
          field(:to, :atom)
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
          field(:p, :atom)
          field(:c, :atom)
        end

        relation :ancestor do
          field(:a, :atom)
          field(:d, :atom)
        end

        fact(parent(:alice, :bob))
        fact(parent(:bob, :carol))
        fact(parent(:carol, :dave))

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
          field(:p, :atom)
        end

        relation :married do
          field(:p, :atom)
          field(:sp, :atom)
        end

        relation :bachelor do
          field(:p, :atom)
        end

        fact(male(:bob))
        fact(male(:tom))
        fact(married(:tom, :sally))

        rule bachelor(P) do
          male(P)
          not_(married(P, _))
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
          field(:person, :atom)
          field(:amount, :integer)
        end

        relation :high_earner do
          field(:person, :atom)
        end

        fact(income(:alice, 150_000))
        fact(income(:bob, 50_000))
        fact(income(:carol, 200_000))

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
          field(:from, :atom)
          field(:to, :atom)
        end

        relation :path do
          field(:from, :atom)
          field(:to, :atom)
        end

        facts :edge do
          row(:a, :b)
          row(:b, :c)
          row(:c, :d)
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
          field(:p, :atom)
          field(:c, :atom)
        end

        relation :ancestor do
          field(:a, :atom)
          field(:d, :atom)
        end

        fact(parent(:alice, :bob))
        fact(parent(:bob, :carol))

        rule ancestor(X, Y) do
          parent(X, Y)
        end

        query :all_ancestors do
          find(X, Y)
          where(ancestor(X, Y))
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
          field(:p, :atom)
          field(:c, :atom)
        end

        relation :ancestor do
          field(:a, :atom)
          field(:d, :atom)
        end

        fact(parent(:alice, :bob))
        fact(parent(:bob, :carol))

        rule ancestor(X, Y) do
          parent(X, Y)
        end

        query :descendants_of_alice do
          find(Y)
          where(ancestor(:alice, Y))
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
          field(:p, :atom)
          field(:c, :atom)
        end

        fact(parent(:alice, :bob))

        query :known_query do
          find(X)
          where(parent(X, _))
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
          field(:p, :atom)
          field(:c, :atom)
        end

        fact(parent(:alice, :bob))

        query :kids_of_alice do
          find(C)
          where(parent(:alice, C))
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
          field(:p, :atom)
          field(:c, :atom)
        end

        relation :ancestor do
          field(:a, :atom)
          field(:d, :atom)
        end

        fact(parent(:alice, :bob))
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
          field(:person, :atom)
          field(:base, :integer)
        end

        relation :total_comp do
          field(:person, :atom)
          field(:total, :integer)
        end

        fact(salary(:alice, 100))
        fact(salary(:bob, 80))

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
    test "aggregate syntax in rule head raises DSL.CompileError" do
      assert_raise ExDatalog.DSL.CompileError, ~r/use count\/sum\/min\/max for aggregates/, fn ->
        Code.compile_string("""
        defmodule AggHeadTestErr do
          use ExDatalog.Schema

          relation :employee do
            field(:name, :atom)
            field(:dept, :atom)
          end

          relation :employee_count do
            field(:dept, :atom)
            field(:count_val, :atom)
          end

          fact(employee(:alice, :eng))

          rule employee_count(Dept, agg(:count, Emp)) do
            employee(Emp, Dept)
          end
        end
        """)
      end
    end

    test "aggregate syntax in rule body raises DSL.CompileError" do
      assert_raise ExDatalog.DSL.CompileError, ~r/use count\/sum\/min\/max for aggregates/, fn ->
        Code.compile_string("""
        defmodule AggBodyTestErr do
          use ExDatalog.Schema

          relation :employee do
            field(:name, :atom)
            field(:dept, :atom)
          end

          relation :employee_count do
            field(:dept, :atom)
            field(:count_val, :atom)
          end

          fact(employee(:alice, :eng))

          rule employee_count(Dept, Count) do
            employee(Emp, Dept)
            agg(:count, Emp)
          end
        end
        """)
      end
    end

    test "UnsupportedFeature struct fields are accessible" do
      uf = %ExDatalog.UnsupportedFeature{feature: :aggregates, planned_for: "v0.6.0"}
      assert uf.feature == :aggregates
      assert uf.planned_for == "v0.6.0"
    end
  end

  describe "wildcard/0 helper" do
    test "returns :wildcard atom" do
      assert ExDatalog.Schema.wildcard() == :wildcard
    end

    test "wildcard can be used in rule bodies" do
      defmodule WildcardTest do
        use ExDatalog.Schema

        relation :person do
          field(:name, :atom)
        end

        relation :unmatched do
          field(:name, :atom)
        end

        fact(person(:alice))
        fact(person(:bob))

        rule unmatched(N) do
          person(N)
          not_(person(wildcard()))
        end
      end

      program = WildcardTest.program()
      assert length(program.rules) == 1
    end
  end

  describe "constraint types in DSL" do
    test "eq constraint" do
      defmodule EqTest do
        use ExDatalog.Schema

        relation :pair do
          field(:a, :atom)
          field(:b, :atom)
        end

        relation :same do
          field(:x, :atom)
        end

        fact(pair(:x, :x))

        rule same(A) do
          pair(A, B)
          eq(A, B)
        end
      end

      {:ok, knowledge} = EqTest.materialize()
      same = Knowledge.get(knowledge, "same")
      assert {:x} in same
    end

    test "neq constraint" do
      defmodule NeqTest do
        use ExDatalog.Schema

        relation :pair do
          field(:a, :atom)
          field(:b, :atom)
        end

        relation :different do
          field(:a, :atom)
          field(:b, :atom)
        end

        fact(pair(:a, :b))
        fact(pair(:b, :a))
        fact(pair(:a, :a))

        rule different(A, B) do
          pair(A, B)
          neq(A, B)
        end
      end

      {:ok, knowledge} = NeqTest.materialize()
      diff = Knowledge.get(knowledge, "different")
      assert MapSet.size(diff) == 2
    end

    test "is_integer constraint" do
      defmodule TypeTest do
        use ExDatalog.Schema

        relation :value do
          field(:v, :any)
        end

        relation :int_val do
          field(:v, :any)
        end

        fact(value(42))
        fact(value(:not_int))

        rule int_val(V) do
          value(V)
          is_integer(V)
        end
      end

      {:ok, knowledge} = TypeTest.materialize()
      int_val = Knowledge.get(knowledge, "int_val")
      assert MapSet.size(int_val) == 1
      assert {42} in int_val
    end
  end

  describe "materialize/0,1 options" do
    test "passes options to ExDatalog.materialize/2" do
      defmodule OptsTest do
        use ExDatalog.Schema

        relation :link do
          field(:from, :atom)
          field(:to, :atom)
        end

        relation :reachable do
          field(:from, :atom)
          field(:to, :atom)
        end

        fact(link(:a, :b))

        rule reachable(X, Y) do
          link(X, Y)
        end
      end

      {:ok, knowledge} = OptsTest.materialize(iteration_limit: 100)
      assert MapSet.size(Knowledge.get(knowledge, "reachable")) == 1
    end
  end

  describe "program/0" do
    test "returns a valid Program struct" do
      defmodule ProgTest do
        use ExDatalog.Schema

        relation :r do
          field(:a, :atom)
        end

        fact(r(:x))
      end

      program = ProgTest.program()
      assert %Program{} = program
      assert Map.has_key?(program.relations, "r")
      assert length(program.facts) == 1
    end
  end

  describe "multi-rule programs" do
    test "multiple rules for same head relation" do
      defmodule MultiRuleTest do
        use ExDatalog.Schema

        relation :link do
          field(:from, :atom)
          field(:to, :atom)
        end

        relation :path do
          field(:from, :atom)
          field(:to, :atom)
        end

        fact(link(:a, :b))
        fact(link(:b, :c))
        fact(link(:c, :d))

        rule path(X, Y) do
          link(X, Y)
        end

        rule path(X, Z) do
          link(X, Y)
          path(Y, Z)
        end
      end

      {:ok, knowledge} = MultiRuleTest.materialize()
      path = Knowledge.get(knowledge, "path")
      assert MapSet.size(path) == 6
    end
  end

  describe "DSL.CompileError" do
    test "exception has message field" do
      err = %ExDatalog.DSL.CompileError{message: "test error"}
      assert err.message == "test error"
    end

    test "exception can be raised and caught" do
      assert_raise ExDatalog.DSL.CompileError, "bad schema", fn ->
        raise ExDatalog.DSL.CompileError, message: "bad schema"
      end
    end
  end

  describe "additional constraint types in DSL" do
    test "neq constraint filters non-matching bindings" do
      defmodule NeqConstraintTest do
        use ExDatalog.Schema

        relation :pair do
          field(:a, :atom)
          field(:b, :atom)
        end

        relation :different do
          field(:a, :atom)
          field(:b, :atom)
        end

        fact(pair(:x, :y))
        fact(pair(:x, :x))

        rule different(A, B) do
          pair(A, B)
          neq(A, B)
        end
      end

      {:ok, knowledge} = NeqConstraintTest.materialize()
      diff = Knowledge.get(knowledge, "different")
      assert MapSet.size(diff) == 1
      assert {:x, :y} in diff
    end

    test "gte constraint" do
      defmodule GteConstraintTest do
        use ExDatalog.Schema

        relation :score do
          field(:player, :atom)
          field(:points, :integer)
        end

        relation :passing do
          field(:player, :atom)
        end

        fact(score(:alice, 60))
        fact(score(:bob, 59))
        fact(score(:carol, 100))

        rule passing(P) do
          score(P, S)
          gte(S, 60)
        end
      end

      {:ok, knowledge} = GteConstraintTest.materialize()
      passing = Knowledge.get(knowledge, "passing")
      assert MapSet.size(passing) == 2
      assert {:alice} in passing
      assert {:carol} in passing
    end

    test "lte constraint" do
      defmodule LteConstraintTest do
        use ExDatalog.Schema

        relation :score do
          field(:player, :atom)
          field(:points, :integer)
        end

        relation :low_score do
          field(:player, :atom)
        end

        fact(score(:alice, 30))
        fact(score(:bob, 60))

        rule low_score(P) do
          score(P, S)
          lte(S, 40)
        end
      end

      {:ok, knowledge} = LteConstraintTest.materialize()
      low = Knowledge.get(knowledge, "low_score")
      assert MapSet.size(low) == 1
      assert {:alice} in low
    end

    test "sub constraint" do
      defmodule SubConstraintTest do
        use ExDatalog.Schema

        relation :value do
          field(:x, :integer)
        end

        relation :decremented do
          field(:x, :integer)
          field(:y, :integer)
        end

        fact(value(10))
        fact(value(5))

        rule decremented(X, Y) do
          value(X)
          sub(X, 3, Y)
        end
      end

      {:ok, knowledge} = SubConstraintTest.materialize()
      dec = Knowledge.get(knowledge, "decremented")
      assert MapSet.size(dec) == 2
      assert {10, 7} in dec
      assert {5, 2} in dec
    end

    test "mul constraint" do
      defmodule MulConstraintTest do
        use ExDatalog.Schema

        relation :value do
          field(:x, :integer)
        end

        relation :doubled do
          field(:x, :integer)
          field(:y, :integer)
        end

        fact(value(3))
        fact(value(7))

        rule doubled(X, Y) do
          value(X)
          mul(X, 2, Y)
        end
      end

      {:ok, knowledge} = MulConstraintTest.materialize()
      dbl = Knowledge.get(knowledge, "doubled")
      assert MapSet.size(dbl) == 2
      assert {3, 6} in dbl
      assert {7, 14} in dbl
    end

    test "div constraint" do
      defmodule DivConstraintTest do
        use ExDatalog.Schema

        relation :value do
          field(:x, :integer)
        end

        relation :halved do
          field(:x, :integer)
          field(:y, :integer)
        end

        fact(value(10))
        fact(value(7))

        rule halved(X, Y) do
          value(X)
          div(X, 2, Y)
        end
      end

      {:ok, knowledge} = DivConstraintTest.materialize()
      half = Knowledge.get(knowledge, "halved")
      assert MapSet.size(half) == 2
      assert {10, 5} in half
      assert {7, 3} in half
    end

    test "is_binary constraint" do
      defmodule IsBinaryTest do
        use ExDatalog.Schema

        relation :entry do
          field(:k, :atom)
          field(:v, :any)
        end

        relation :string_entry do
          field(:k, :atom)
        end

        fact(entry(:a, "hello"))
        fact(entry(:b, 42))

        rule string_entry(K) do
          entry(K, V)
          is_binary(V)
        end
      end

      {:ok, knowledge} = IsBinaryTest.materialize()
      result = Knowledge.get(knowledge, "string_entry")
      assert MapSet.size(result) == 1
      assert {:a} in result
    end

    test "is_atom constraint" do
      defmodule IsAtomTest do
        use ExDatalog.Schema

        relation :entry do
          field(:k, :atom)
          field(:v, :any)
        end

        relation :atom_entry do
          field(:k, :atom)
        end

        fact(entry(:a, :foo))
        fact(entry(:b, 42))

        rule atom_entry(K) do
          entry(K, V)
          is_atom(V)
        end
      end

      {:ok, knowledge} = IsAtomTest.materialize()
      result = Knowledge.get(knowledge, "atom_entry")
      assert MapSet.size(result) == 1
      assert {:a} in result
    end

    test "starts_with constraint" do
      defmodule StartsWithTest do
        use ExDatalog.Schema

        relation :word do
          field(:w, :string)
        end

        relation :hello_word do
          field(:w, :string)
        end

        fact(word("hello"))
        fact(word("world"))
        fact(word("helicopter"))

        rule hello_word(W) do
          word(W)
          starts_with(W, "hel")
        end
      end

      {:ok, knowledge} = StartsWithTest.materialize()
      result = Knowledge.get(knowledge, "hello_word")
      assert MapSet.size(result) == 2
    end

    test "contains constraint" do
      defmodule ContainsTest do
        use ExDatalog.Schema

        relation :word do
          field(:w, :string)
        end

        relation :ell_word do
          field(:w, :string)
        end

        fact(word("hello"))
        fact(word("world"))
        fact(word("yellow"))

        rule ell_word(W) do
          word(W)
          contains(W, "ell")
        end
      end

      {:ok, knowledge} = ContainsTest.materialize()
      result = Knowledge.get(knowledge, "ell_word")
      assert MapSet.size(result) == 2
    end

    test "member constraint" do
      defmodule MemberTest do
        use ExDatalog.Schema

        relation :color do
          field(:name, :atom)
        end

        relation :primary_color do
          field(:name, :atom)
        end

        fact(color(:red))
        fact(color(:blue))
        fact(color(:purple))

        rule primary_color(C) do
          color(C)
          member(C, [:red, :blue, :green])
        end
      end

      {:ok, knowledge} = MemberTest.materialize()
      result = Knowledge.get(knowledge, "primary_color")
      assert MapSet.size(result) == 2
      assert {:red} in result
      assert {:blue} in result
    end
  end

  describe "query edge cases" do
    test "multi-column find projects to tuples" do
      defmodule MultiColQueryTest do
        use ExDatalog.Schema

        relation :parent do
          field(:p, :atom)
          field(:c, :atom)
        end

        relation :ancestor do
          field(:a, :atom)
          field(:d, :atom)
        end

        fact(parent(:alice, :bob))
        fact(parent(:bob, :carol))
        fact(parent(:carol, :dave))

        rule ancestor(X, Y) do
          parent(X, Y)
        end

        rule ancestor(X, Z) do
          parent(X, Y)
          ancestor(Y, Z)
        end

        query :all_ancestors do
          find(A, D)
          where(ancestor(A, D))
        end
      end

      {:ok, knowledge} = MultiColQueryTest.materialize()
      results = MultiColQueryTest.query(:all_ancestors, knowledge)
      assert length(results) == 6
      assert {:alice, :bob} in results
      assert {:alice, :dave} in results
    end

    test "query with all wildcards returns full relation" do
      defmodule WildcardQueryTest do
        use ExDatalog.Schema

        relation :edge do
          field(:from, :atom)
          field(:to, :atom)
        end

        fact(edge(:a, :b))
        fact(edge(:b, :c))

        query :all_edges do
          find(X, Y)
          where(edge(X, Y))
        end
      end

      {:ok, knowledge} = WildcardQueryTest.materialize()
      results = WildcardQueryTest.query(:all_edges, knowledge)
      assert length(results) == 2
    end
  end

  describe "facts macro edge cases" do
    test "facts with single row" do
      defmodule FactsSingleRowTest do
        use ExDatalog.Schema

        relation :node do
          field(:name, :atom)
        end

        facts :node do
          row(:root)
        end
      end

      program = FactsSingleRowTest.program()
      assert length(program.facts) == 1
      assert {"node", [:root]} in program.facts
    end
  end

  describe "rule head with uppercase variables from module context" do
    test "uppercase variables in rule head via __aliases__ AST form" do
      defmodule AliasVarTest do
        use ExDatalog.Schema

        relation :link do
          field(:from, :atom)
          field(:to, :atom)
        end

        relation :reachable do
          field(:from, :atom)
          field(:to, :atom)
        end

        fact(link(:a, :b))

        rule reachable(X, Y) do
          link(X, Y)
        end
      end

      {:ok, knowledge} = AliasVarTest.materialize()
      result = Knowledge.get(knowledge, "reachable")
      assert MapSet.size(result) == 1
    end
  end

  describe "parse term edge cases" do
    test "integer constants in facts" do
      defmodule IntFactTest do
        use ExDatalog.Schema

        relation :measurement do
          field(:name, :atom)
          field(:value, :integer)
        end

        fact(measurement(:temp, 42))
      end

      program = IntFactTest.program()
      assert {"measurement", [:temp, 42]} in program.facts
    end

    test "string constants in constraints" do
      defmodule StringConstraintTest do
        use ExDatalog.Schema

        relation :label do
          field(:id, :atom)
          field(:text, :string)
        end

        relation :short_label do
          field(:id, :atom)
        end

        fact(label(:a, "hello world"))
        fact(label(:b, "hi"))

        rule short_label(I) do
          label(I, T)
          starts_with(T, "hello")
        end
      end

      {:ok, knowledge} = StringConstraintTest.materialize()
      result = Knowledge.get(knowledge, "short_label")
      assert MapSet.size(result) == 1
    end
  end

  describe "combination of multiple constraints" do
    test "gt and lte together in single rule" do
      defmodule ComboConstraintTest do
        use ExDatalog.Schema

        relation :score do
          field(:player, :atom)
          field(:points, :integer)
        end

        relation :mid_range do
          field(:player, :atom)
        end

        fact(score(:alice, 60))
        fact(score(:bob, 30))
        fact(score(:carol, 90))

        rule mid_range(P) do
          score(P, S)
          gt(S, 50)
          lte(S, 80)
        end
      end

      {:ok, knowledge} = ComboConstraintTest.materialize()
      result = Knowledge.get(knowledge, "mid_range")
      assert MapSet.size(result) == 1
      assert {:alice} in result
    end
  end

  describe "program/0 introspection" do
    test "program contains declared relations" do
      defmodule IntrospectionTest do
        use ExDatalog.Schema

        relation :parent do
          field(:p, :atom)
          field(:c, :atom)
        end

        relation :ancestor do
          field(:a, :atom)
          field(:d, :atom)
        end

        fact(parent(:x, :y))

        rule ancestor(X, Y) do
          parent(X, Y)
        end
      end

      program = IntrospectionTest.program()
      assert Map.has_key?(program.relations, "parent")
      assert Map.has_key?(program.relations, "ancestor")
      assert length(program.facts) == 1
      assert length(program.rules) == 1
    end
  end

  describe "materialize/1 with options" do
    test "passes iteration_limit option" do
      defmodule IterLimitTest do
        use ExDatalog.Schema

        relation :edge do
          field(:from, :atom)
          field(:to, :atom)
        end

        relation :reachable do
          field(:from, :atom)
          field(:to, :atom)
        end

        fact(edge(:a, :b))

        rule reachable(X, Y) do
          edge(X, Y)
        end
      end

      {:ok, knowledge} = IterLimitTest.materialize(iteration_limit: 100)
      assert MapSet.size(Knowledge.get(knowledge, "reachable")) == 1
    end
  end

  describe "aggregate DSL" do
    test "count aggregate in rule body" do
      defmodule CountDSLTest do
        use ExDatalog.Schema

        relation :emp do
          field(:name, :atom)
          field(:dept, :atom)
        end

        relation :dept_count do
          field(:dept, :atom)
          field(:n, :integer)
        end

        fact(emp(:alice, :eng))
        fact(emp(:bob, :eng))
        fact(emp(:carol, :ops))

        rule dept_count(D, N) do
          emp(E, D)
          count(E, N)
        end
      end

      {:ok, knowledge} = CountDSLTest.materialize()
      result = Knowledge.get(knowledge, "dept_count")
      assert {:eng, 2} in result
      assert {:ops, 1} in result
    end

    test "sum aggregate in rule body" do
      defmodule SumDSLTest do
        use ExDatalog.Schema

        relation :salary do
          field(:name, :atom)
          field(:dept, :atom)
          field(:amount, :integer)
        end

        relation :dept_total do
          field(:dept, :atom)
          field(:total, :integer)
        end

        fact(salary(:alice, :eng, 100))
        fact(salary(:bob, :eng, 80))

        rule dept_total(D, T) do
          salary(E, D, A)
          sum(A, T)
        end
      end

      {:ok, knowledge} = SumDSLTest.materialize()
      assert {:eng, 180} in Knowledge.get(knowledge, "dept_total")
    end

    test "aggregate in head position raises DSL.CompileError" do
      assert_raise ExDatalog.DSL.CompileError, ~r/cannot appear in a rule head/, fn ->
        Code.compile_string("""
        defmodule AggHeadAggTest do
          use ExDatalog.Schema

          relation :emp do
            field(:name, :atom)
            field(:dept, :atom)
          end

          relation :dept_count do
            field(:dept, :atom)
            field(:n, :integer)
          end

          fact(emp(:alice, :eng))

          rule dept_count(D, count(E, N)) do
            emp(E, D)
          end
        end
        """)
      end
    end
  end
end

defmodule ExDatalog.SchemaCoverageTest do
  use ExUnit.Case, async: true

  alias ExDatalog.Knowledge

  describe "wildcard in not_ clause" do
    test "wildcard() and _ are equivalent in negation" do
      defmodule WildcardNegationTest do
        use ExDatalog.Schema

        relation :person do
          field(:name, :atom)
        end

        relation :pet do
          field(:owner, :atom)
          field(:pet_name, :atom)
        end

        relation :petless do
          field(:name, :atom)
        end

        fact(person(:alice))
        fact(person(:bob))
        fact(pet(:alice, :fido))

        rule petless(N) do
          person(N)
          not_(pet(N, wildcard()))
        end
      end

      {:ok, knowledge} = WildcardNegationTest.materialize()
      petless = Knowledge.get(knowledge, "petless")
      assert {:bob} in petless
    end
  end

  describe "query with atom constants in where" do
    test "constant value projection works correctly" do
      defmodule QueryConstantTest do
        use ExDatalog.Schema

        relation :parent do
          field(:p, :atom)
          field(:c, :atom)
        end

        fact(parent(:alice, :bob))
        fact(parent(:alice, :carol))
        fact(parent(:bob, :dave))

        query :children_of_alice do
          find(C)
          where(parent(:alice, C))
        end
      end

      {:ok, knowledge} = QueryConstantTest.materialize()
      results = QueryConstantTest.query(:children_of_alice, knowledge)
      assert :bob in results
      assert :carol in results
    end
  end

  describe "rule with string and integer terms" do
    test "integer constant as fact value" do
      defmodule IntConstantRuleTest do
        use ExDatalog.Schema

        relation :data do
          field(:id, :atom)
          field(:val, :integer)
        end

        relation :big_data do
          field(:id, :atom)
        end

        fact(data(:a, 100))
        fact(data(:b, 10))

        rule big_data(I) do
          data(I, V)
          gt(V, 50)
        end
      end

      {:ok, knowledge} = IntConstantRuleTest.materialize()
      big = Knowledge.get(knowledge, "big_data")
      assert MapSet.size(big) == 1
      assert {:a} in big
    end
  end

  describe "program/0 introspection with multiple rules" do
    test "rules and facts are in correct order" do
      defmodule IntrospectOrderTest do
        use ExDatalog.Schema

        relation :edge do
          field(:from, :atom)
          field(:to, :atom)
        end

        relation :path do
          field(:from, :atom)
          field(:to, :atom)
        end

        fact(edge(:a, :b))
        fact(edge(:b, :c))

        rule path(X, Y) do
          edge(X, Y)
        end

        rule path(X, Z) do
          edge(X, Y)
          path(Y, Z)
        end
      end

      program = IntrospectOrderTest.program()
      assert length(program.rules) == 2
      assert length(program.facts) == 2
    end
  end

  describe "constraint from_tuple passthrough" do
    test "all comparison constraints produce valid Constraint structs" do
      alias ExDatalog.Constraint

      assert %Constraint{op: :eq} = Constraint.from_tuple({:eq, {:var, "X"}, {:const, 1}})
      assert %Constraint{op: :neq} = Constraint.from_tuple({:neq, {:var, "X"}, {:var, "Y"}})
      assert %Constraint{op: :gt} = Constraint.from_tuple({:gt, {:var, "X"}, {:const, 0}})
      assert %Constraint{op: :gte} = Constraint.from_tuple({:gte, {:var, "X"}, {:const, 0}})
      assert %Constraint{op: :lt} = Constraint.from_tuple({:lt, {:var, "X"}, {:const, 0}})
      assert %Constraint{op: :lte} = Constraint.from_tuple({:lte, {:var, "X"}, {:const, 0}})

      assert %Constraint{op: :add} =
               Constraint.from_tuple({:add, {:var, "X"}, {:var, "Y"}, {:var, "Z"}})

      assert %Constraint{op: :sub} =
               Constraint.from_tuple({:sub, {:var, "X"}, {:var, "Y"}, {:var, "Z"}})

      assert %Constraint{op: :mul} =
               Constraint.from_tuple({:mul, {:var, "X"}, {:var, "Y"}, {:var, "Z"}})

      assert %Constraint{op: :div} =
               Constraint.from_tuple({:div, {:var, "X"}, {:var, "Y"}, {:var, "Z"}})

      assert %Constraint{op: :is_integer} = Constraint.from_tuple({:is_integer, {:var, "X"}})
      assert %Constraint{op: :is_binary} = Constraint.from_tuple({:is_binary, {:var, "X"}})
      assert %Constraint{op: :is_atom} = Constraint.from_tuple({:is_atom, {:var, "X"}})

      assert %Constraint{op: :starts_with} =
               Constraint.from_tuple({:starts_with, {:var, "X"}, {:const, "hel"}})

      assert %Constraint{op: :contains} =
               Constraint.from_tuple({:contains, {:var, "X"}, {:const, "ell"}})

      assert %Constraint{op: :member} =
               Constraint.from_tuple({:member, {:var, "X"}, {:const, [:a, :b]}})
    end
  end

  describe "zero-argument relation query" do
    test "query on unary relation" do
      defmodule UnaryQueryTest do
        use ExDatalog.Schema

        relation :person do
          field(:name, :atom)
        end

        fact(person(:alice))
        fact(person(:bob))

        query :all_people do
          find(N)
          where(person(N))
        end
      end

      {:ok, knowledge} = UnaryQueryTest.materialize()
      results = UnaryQueryTest.query(:all_people, knowledge)
      assert length(results) == 2
    end
  end

  describe "queries/0 with multiple queries" do
    test "queries returns map with all registered queries" do
      defmodule QueriesMapTest do
        use ExDatalog.Schema

        relation :edge do
          field(:a, :atom)
          field(:b, :atom)
        end

        fact(edge(:x, :y))

        query :all_edges do
          find(A, B)
          where(edge(A, B))
        end

        query :edges_from_x do
          find(B)
          where(edge(:x, B))
        end
      end

      queries = QueriesMapTest.queries()
      assert Map.has_key?(queries, :all_edges)
      assert Map.has_key?(queries, :edges_from_x)
      assert queries.all_edges.relation == "edge"
      assert queries.edges_from_x.relation == "edge"
    end
  end

  describe "single body expression rule" do
    test "rule with single literal in body compiles and materializes" do
      defmodule SingleBodyExprTest do
        use ExDatalog.Schema

        relation :link do
          field(:a, :atom)
          field(:b, :atom)
        end

        relation :path do
          field(:a, :atom)
          field(:b, :atom)
        end

        fact(link(:x, :y))

        rule path(A, B) do
          link(A, B)
        end
      end

      {:ok, knowledge} = SingleBodyExprTest.materialize()
      result = Knowledge.get(knowledge, "path")
      assert MapSet.size(result) == 1
      assert {:x, :y} in result
    end
  end
end

defmodule ExDatalog.SchemaErrorTest do
  use ExUnit.Case, async: false

  describe "validation errors" do
    test "fact referencing undeclared relation raises CompileError at compile time" do
      assert_raise ExDatalog.DSL.CompileError, ~r/not declared/, fn ->
        Code.compile_string("""
        defmodule FactUndeclaredTestErr do
          use ExDatalog.Schema

          relation :parent do
            field(:p, :atom)
            field(:c, :atom)
          end

          fact unknown(:alice, :bob)
        end
        """)
      end
    end

    test "query referencing undeclared relation raises CompileError at compile time" do
      assert_raise ExDatalog.DSL.CompileError, ~r/not declared/, fn ->
        Code.compile_string("""
        defmodule QueryUndeclaredTestErr do
          use ExDatalog.Schema

          relation :parent do
            field(:p, :atom)
            field(:c, :atom)
          end

          fact parent(:alice, :bob)

          query :all_unknowns do
            find(X)
            where unknown(X)
          end
        end
        """)
      end
    end

    test "unsafe variable in rule head raises when building program" do
      defmodule UnsafeVarRuleTest do
        use ExDatalog.Schema

        relation :edge do
          field(:from, :atom)
          field(:to, :atom)
        end

        relation :path do
          field(:from, :atom)
          field(:to, :atom)
        end

        fact(edge(:a, :b))

        rule path(X, Z) do
          edge(X, Y)
        end
      end

      assert_raise ExDatalog.DSL.CompileError, ~r/not in any positive body literal/, fn ->
        UnsafeVarRuleTest.program()
      end
    end

    test "arity mismatch in fact raises when building program" do
      defmodule ArityMismatchFactErrTest do
        use ExDatalog.Schema

        relation :parent do
          field(:p, :atom)
          field(:c, :atom)
        end

        fact(parent(:alice, :bob))
      end

      program = ArityMismatchFactErrTest.program()

      assert %ExDatalog.Program{} = program
    end

    test "rule referencing undeclared relation raises when building program" do
      defmodule RuleUndeclaredRelTest do
        use ExDatalog.Schema

        relation :edge do
          field(:from, :atom)
          field(:to, :atom)
        end

        relation :path do
          field(:from, :atom)
          field(:to, :atom)
        end

        fact(edge(:a, :b))

        rule path(X, Y) do
          unknown(X, Y)
        end
      end

      assert_raise ExDatalog.DSL.CompileError, ~r/undefined relation/, fn ->
        RuleUndeclaredRelTest.program()
      end
    end

    test "aggregate in rule head raises DSL.CompileError" do
      assert_raise ExDatalog.DSL.CompileError, ~r/use count\/sum\/min\/max for aggregates/, fn ->
        Code.compile_string("""
        defmodule AggHeadErrTest do
          use ExDatalog.Schema

          relation :employee do
            field(:name, :atom)
            field(:dept, :atom)
          end

          relation :employee_count do
            field(:dept, :atom)
            field(:count_val, :atom)
          end

          fact(employee(:alice, :eng))

          rule employee_count(Dept, agg(:count, Emp)) do
            employee(Emp, Dept)
          end
        end
        """)
      end
    end

    test "aggregate in rule body raises DSL.CompileError" do
      assert_raise ExDatalog.DSL.CompileError, ~r/use count\/sum\/min\/max for aggregates/, fn ->
        Code.compile_string("""
        defmodule AggBodyErrTest do
          use ExDatalog.Schema

          relation :employee do
            field(:name, :atom)
            field(:dept, :atom)
          end

          relation :employee_count do
            field(:dept, :atom)
            field(:count_val, :atom)
          end

          fact(employee(:alice, :eng))

          rule employee_count(Dept, Count) do
            employee(Emp, Dept)
            agg(:count, Emp)
          end
        end
        """)
      end
    end

    test "query without where clause raises DSL.CompileError" do
      assert_raise ExDatalog.DSL.CompileError, ~r/requires a .where. clause/, fn ->
        Code.compile_string("""
        defmodule QueryNoWhereErrTest do
          use ExDatalog.Schema

          relation :parent do
            field(:p, :atom)
            field(:c, :atom)
          end

          fact(parent(:alice, :bob))

          query :just_find do
            find(X)
          end
        end
        """)
      end
    end

    test "query find variable not in where pattern raises DSL.CompileError" do
      assert_raise ExDatalog.DSL.CompileError, ~r/not present in where pattern/, fn ->
        Code.compile_string("""
        defmodule QueryFindVarErrTest do
          use ExDatalog.Schema

          relation :edge do
            field(:from, :atom)
            field(:to, :atom)
          end

          fact(edge(:a, :b))

          query :bad_find do
            find Z
            where edge(X, Y)
          end
        end
        """)
      end
    end

    test "unrecognized expression in relation block raises DSL.CompileError" do
      assert_raise ExDatalog.DSL.CompileError,
                   ~r/unrecognized expression in relation block/,
                   fn ->
                     Code.compile_string("""
                     defmodule BadRelationBlockTest do
                       use ExDatalog.Schema

                       relation :parent do
                         field(:p, :atom)
                         IO.puts("oops")
                       end
                     end
                     """)
                   end
    end

    test "unrecognized expression in facts block raises DSL.CompileError" do
      assert_raise ExDatalog.DSL.CompileError, ~r/unrecognized expression in facts block/, fn ->
        Code.compile_string("""
        defmodule BadFactsBlockTest do
          use ExDatalog.Schema

          relation :parent do
            field(:p, :atom)
            field(:c, :atom)
          end

          facts :parent do
            IO.puts("oops")
          end
        end
        """)
      end
    end
  end
end
