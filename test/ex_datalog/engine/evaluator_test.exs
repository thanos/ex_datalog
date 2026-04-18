defmodule ExDatalog.Engine.EvaluatorTest do
  use ExUnit.Case, async: true

  alias ExDatalog.Engine.Evaluator
  alias ExDatalog.IR

  describe "eval_rule_iteration/4" do
    test "single-atom body rule derives from delta" do
      head = %IR.Atom{relation: "ancestor", terms: [{:var, "X"}, {:var, "Y"}]}
      body = [{:positive, %IR.Atom{relation: "parent", terms: [{:var, "X"}, {:var, "Y"}]}}]
      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 0, metadata: %{}}

      delta = %{"parent" => MapSet.new([{:alice, :bob}, {:carol, :dave}])}
      full = delta
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert length(result) == 2
      assert {:alice, :bob} in result
      assert {:carol, :dave} in result
    end

    test "two-atom body rule with non-empty old" do
      head = %IR.Atom{relation: "path", terms: [{:var, "X"}, {:var, "Z"}]}

      body = [
        {:positive, %IR.Atom{relation: "edge", terms: [{:var, "X"}, {:var, "Y"}]}},
        {:positive, %IR.Atom{relation: "edge", terms: [{:var, "Y"}, {:var, "Z"}]}}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 0, metadata: %{}}

      parent = %{"edge" => MapSet.new([{:a, :b}, {:b, :c}])}
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, parent, parent, old)
      assert length(result) == 1
      assert {:a, :c} in result
    end

    test "rule with constraint filter" do
      head = %IR.Atom{relation: "big", terms: [{:var, "X"}]}
      body = [{:positive, %IR.Atom{relation: "val", terms: [{:var, "X"}]}}]

      constraints = [
        {:constraint,
         %IR.Constraint{op: :gt, left: {:var, "X"}, right: {:const, {:int, 5}}, result: nil}}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body ++ constraints, stratum: 0, metadata: %{}}

      full = %{"val" => MapSet.new([{3}, {7}, {10}])}
      delta = full
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert length(result) == 2
      assert {7} in result
      assert {10} in result
    end

    test "rule with arithmetic constraint" do
      head = %IR.Atom{relation: "sum", terms: [{:var, "X"}, {:var, "Y"}, {:var, "Z"}]}

      body = [
        {:positive, %IR.Atom{relation: "pair", terms: [{:var, "X"}, {:var, "Y"}]}},
        {:constraint,
         %IR.Constraint{
           op: :add,
           left: {:var, "X"},
           right: {:var, "Y"},
           result: {:var, "Z"}
         }}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 0, metadata: %{}}

      full = %{"pair" => MapSet.new([{3, 7}])}
      delta = full
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert length(result) == 1
      assert {3, 7, 10} in result
    end

    test "deduplicates against existing head facts" do
      head = %IR.Atom{relation: "parent", terms: [{:var, "X"}, {:var, "Y"}]}
      body = [{:positive, %IR.Atom{relation: "parent", terms: [{:var, "X"}, {:var, "Y"}]}}]
      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 0, metadata: %{}}

      full = %{"parent" => MapSet.new([{:alice, :bob}])}
      delta = %{"parent" => MapSet.new([{:alice, :bob}])}
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert result == []
    end
  end

  describe "eval_rule_iteration/4 with negation" do
    test "negative atom filters out matching bindings" do
      # bachelor(X) :- male(X), not married(X, _).
      # male = {alice, bob}, married = {(alice, carol)}
      # Only bob should be a bachelor.
      head = %IR.Atom{relation: "bachelor", terms: [{:var, "X"}]}

      body = [
        {:positive, %IR.Atom{relation: "male", terms: [{:var, "X"}]}},
        {:negative, %IR.Atom{relation: "married", terms: [{:var, "X"}, :wildcard]}}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 1, metadata: %{}}

      full = %{
        "male" => MapSet.new([{:alice}, {:bob}]),
        "married" => MapSet.new([{:alice, :carol}])
      }

      delta = %{"male" => MapSet.new([{:alice}, {:bob}])}
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert length(result) == 1
      assert {:bob} in result
    end

    test "negative atom with bound variable filters precisely" do
      # unlike(X, Y) :- likes(X, Z), likes(Y, Z), not friends(X, Y).
      head = %IR.Atom{relation: "unlike", terms: [{:var, "X"}, {:var, "Y"}]}

      body = [
        {:positive, %IR.Atom{relation: "likes", terms: [{:var, "X"}, {:var, "Z"}]}},
        {:positive, %IR.Atom{relation: "likes", terms: [{:var, "Y"}, {:var, "Z"}]}},
        {:negative, %IR.Atom{relation: "friends", terms: [{:var, "X"}, {:var, "Y"}]}}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 1, metadata: %{}}

      full = %{
        "likes" => MapSet.new([{:alice, :pizza}, {:bob, :pizza}, {:carol, :pizza}]),
        "friends" => MapSet.new([{:alice, :bob}])
      }

      delta = %{"likes" => MapSet.new([{:alice, :pizza}, {:bob, :pizza}, {:carol, :pizza}])}
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)

      assert {:alice, :carol} in result
      assert {:bob, :carol} in result
      assert {:carol, :alice} in result
      assert {:carol, :bob} in result
      refute {:alice, :bob} in result
    end

    test "negative atom passes when relation is empty" do
      # If no one is married, all males are bachelors.
      head = %IR.Atom{relation: "bachelor", terms: [{:var, "X"}]}

      body = [
        {:positive, %IR.Atom{relation: "male", terms: [{:var, "X"}]}},
        {:negative, %IR.Atom{relation: "married", terms: [{:var, "X"}, :wildcard]}}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 1, metadata: %{}}

      full = %{
        "male" => MapSet.new([{:alice}, {:bob}]),
        "married" => MapSet.new([])
      }

      delta = %{"male" => MapSet.new([{:alice}, {:bob}])}
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert length(result) == 2
      assert {:alice} in result
      assert {:bob} in result
    end

    test "multiple negative atoms are all required" do
      # verified(X) :- candidate(X), not blocked(X), not rejected(X).
      head = %IR.Atom{relation: "verified", terms: [{:var, "X"}]}

      body = [
        {:positive, %IR.Atom{relation: "candidate", terms: [{:var, "X"}]}},
        {:negative, %IR.Atom{relation: "blocked", terms: [{:var, "X"}]}},
        {:negative, %IR.Atom{relation: "rejected", terms: [{:var, "X"}]}}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 1, metadata: %{}}

      full = %{
        "candidate" => MapSet.new([{:alice}, {:bob}, {:carol}]),
        "blocked" => MapSet.new([{:bob}]),
        "rejected" => MapSet.new([{:carol}])
      }

      delta = %{"candidate" => MapSet.new([{:alice}, {:bob}, {:carol}])}
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert result == [{:alice}]
    end

    test "negative atom with constant term" do
      # not_married_to_alice(X) :- male(X), not married(X, alice).
      head = %IR.Atom{relation: "not_married_to_alice", terms: [{:var, "X"}]}

      body = [
        {:positive, %IR.Atom{relation: "male", terms: [{:var, "X"}]}},
        {:negative,
         %IR.Atom{relation: "married", terms: [{:var, "X"}, {:const, {:atom, :alice}}]}}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 1, metadata: %{}}

      full = %{
        "male" => MapSet.new([{:bob}, {:carol}]),
        "married" => MapSet.new([{:bob, :alice}])
      }

      delta = %{"male" => MapSet.new([{:bob}, {:carol}])}
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert result == [{:carol}]
    end

    test "negative atom combined with constraint" do
      # senior_unmarried(X) :- person(X), not married(X, _), X > 20.
      head = %IR.Atom{relation: "senior_unmarried", terms: [{:var, "X"}]}

      body = [
        {:positive, %IR.Atom{relation: "person_age", terms: [{:var, "X"}]}},
        {:negative, %IR.Atom{relation: "married", terms: [{:var, "X"}, :wildcard]}},
        {:constraint,
         %IR.Constraint{op: :gt, left: {:var, "X"}, right: {:const, {:int, 20}}, result: nil}}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 1, metadata: %{}}

      full = %{
        "person_age" => MapSet.new([{15}, {25}, {30}]),
        "married" => MapSet.new([{25, :spouse}])
      }

      delta = %{"person_age" => MapSet.new([{15}, {25}, {30}])}
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert result == [{30}]
    end
  end

  describe "check_negative_atom/3" do
    test "returns true when no tuple matches" do
      atom = %IR.Atom{relation: "married", terms: [{:var, "X"}, :wildcard]}
      binding = %{"X" => :alice}
      full = %{"married" => MapSet.new([{:bob, :carol}])}

      assert Evaluator.check_negative_atom(atom, binding, full) == true
    end

    test "returns false when a tuple matches" do
      atom = %IR.Atom{relation: "married", terms: [{:var, "X"}, :wildcard]}
      binding = %{"X" => :alice}
      full = %{"married" => MapSet.new([{:alice, :carol}])}

      assert Evaluator.check_negative_atom(atom, binding, full) == false
    end

    test "returns true when relation is empty" do
      atom = %IR.Atom{relation: "married", terms: [{:var, "X"}, :wildcard]}
      binding = %{"X" => :alice}
      full = %{"married" => MapSet.new()}

      assert Evaluator.check_negative_atom(atom, binding, full) == true
    end

    test "returns true when relation is missing from full" do
      atom = %IR.Atom{relation: "married", terms: [{:var, "X"}, :wildcard]}
      binding = %{"X" => :alice}
      full = %{}

      assert Evaluator.check_negative_atom(atom, binding, full) == true
    end

    test "constant term in negative atom filters correctly" do
      atom = %IR.Atom{relation: "married", terms: [{:var, "X"}, {:const, {:atom, :carol}}]}
      binding = %{"X" => :alice}
      full = %{"married" => MapSet.new([{:alice, :carol}, {:bob, :dave}])}

      assert Evaluator.check_negative_atom(atom, binding, full) == false
    end
  end
end
