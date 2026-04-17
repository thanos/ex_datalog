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
end
