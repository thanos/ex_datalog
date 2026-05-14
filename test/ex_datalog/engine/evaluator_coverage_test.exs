defmodule ExDatalog.Engine.EvaluatorTest.Coverage do
  use ExUnit.Case, async: true

  alias ExDatalog.Engine.Evaluator
  alias ExDatalog.IR

  describe "eval_rule_iteration/4 — fact rules (k=0)" do
    test "fact rule with no positive atoms derives from constraints only" do
      head = %IR.Atom{relation: "fact", terms: [{:const, {:atom, :always}}]}

      body = [
        {:constraint,
         %IR.Constraint{
           op: :eq,
           left: {:const, {:int, 1}},
           right: {:const, {:int, 1}},
           result: nil
         }}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 0, metadata: %{}}

      full = %{}
      delta = %{}
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert result == [{:always}]
    end

    test "fact rule with no positive atoms and failing constraint produces nothing" do
      head = %IR.Atom{relation: "fact", terms: [{:const, {:atom, :never}}]}

      body = [
        {:constraint,
         %IR.Constraint{
           op: :eq,
           left: {:const, {:int, 1}},
           right: {:const, {:int, 2}},
           result: nil
         }}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 0, metadata: %{}}

      full = %{}
      delta = %{}
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert result == []
    end

    test "constraint and negation together in fact-rule body (k=0 fallback)" do
      head = %IR.Atom{relation: "safe_value", terms: [{:var, "X"}]}

      body = [
        {:positive, %IR.Atom{relation: "val", terms: [{:var, "X"}]}},
        {:negative, %IR.Atom{relation: "blocked", terms: [{:var, "X"}]}},
        {:constraint,
         %IR.Constraint{op: :gt, left: {:var, "X"}, right: {:const, {:int, 0}}, result: nil}}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 1, metadata: %{}}

      full = %{
        "val" => MapSet.new([{5}, {10}, {-3}]),
        "blocked" => MapSet.new([{10}])
      }

      delta = %{"val" => MapSet.new([{5}, {10}, {-3}])}
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert result == [{5}]
    end
  end

  describe "eval_rule_iteration/4 — empty delta optimization" do
    test "returns empty list when delta is empty for all positive body relations" do
      head = %IR.Atom{relation: "path", terms: [{:var, "X"}, {:var, "Y"}]}

      body = [
        {:positive, %IR.Atom{relation: "edge", terms: [{:var, "X"}, {:var, "Y"}]}}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 0, metadata: %{}}

      full = %{"edge" => MapSet.new([{:a, :b}])}
      delta = %{"edge" => MapSet.new([])}
      old = %{"edge" => MapSet.new([])}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert result == []
    end
  end

  describe "eval_rule_iteration/4 — multi-atom with old/delta split" do
    test "two-atom rule uses old for positions after delta" do
      head = %IR.Atom{relation: "path", terms: [{:var, "X"}, {:var, "Z"}]}

      body = [
        {:positive, %IR.Atom{relation: "edge", terms: [{:var, "X"}, {:var, "Y"}]}},
        {:positive, %IR.Atom{relation: "edge", terms: [{:var, "Y"}, {:var, "Z"}]}}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 0, metadata: %{}}

      full = %{"edge" => MapSet.new([{:a, :b}, {:b, :c}, {:c, :d}])}
      delta = %{"edge" => MapSet.new([{:a, :b}])}
      old = %{"edge" => MapSet.new([{:b, :c}, {:c, :d}])}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert {:a, :c} in result
    end

    test "three-atom rule evaluates all delta position variants" do
      head = %IR.Atom{relation: "triple", terms: [{:var, "A"}, {:var, "B"}, {:var, "C"}]}

      body = [
        {:positive, %IR.Atom{relation: "link", terms: [{:var, "A"}, {:var, "B"}]}},
        {:positive, %IR.Atom{relation: "link", terms: [{:var, "B"}, {:var, "X"}]}},
        {:positive, %IR.Atom{relation: "link", terms: [{:var, "X"}, {:var, "C"}]}}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 0, metadata: %{}}

      full = %{"link" => MapSet.new([{:a, :b}, {:b, :x}, {:x, :c}])}
      delta = %{"link" => MapSet.new([{:a, :b}])}
      old = %{"link" => MapSet.new([{:b, :x}, {:x, :c}])}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert {:a, :b, :c} in result
    end
  end

  describe "eval_rule_iteration/4 — constraint + negation in multi-atom bodies" do
    test "constraint in multi-atom body filters joined bindings" do
      head = %IR.Atom{relation: "tall_pair", terms: [{:var, "X"}, {:var, "Y"}]}

      body = [
        {:positive, %IR.Atom{relation: "height", terms: [{:var, "X"}, {:var, "H1"}]}},
        {:positive, %IR.Atom{relation: "height", terms: [{:var, "Y"}, {:var, "H2"}]}},
        {:constraint,
         %IR.Constraint{
           op: :gt,
           left: {:var, "H1"},
           right: {:var, "H2"},
           result: nil
         }}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 0, metadata: %{}}

      full = %{
        "height" => MapSet.new([{:alice, 170}, {:bob, 180}, {:carol, 160}])
      }

      delta = full
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert {:bob, :alice} in result
      assert {:bob, :carol} in result
      assert {:alice, :carol} in result
      refute {:alice, :bob} in result
      refute {:carol, :bob} in result
    end

    test "arithmetic constraint in multi-atom body extends binding" do
      head = %IR.Atom{relation: "total", terms: [{:var, "X"}, {:var, "Y"}, {:var, "Z"}]}

      body = [
        {:positive, %IR.Atom{relation: "val", terms: [{:var, "X"}, {:var, "A"}]}},
        {:positive, %IR.Atom{relation: "val", terms: [{:var, "Y"}, {:var, "B"}]}},
        {:constraint,
         %IR.Constraint{
           op: :add,
           left: {:var, "A"},
           right: {:var, "B"},
           result: {:var, "Z"}
         }}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 0, metadata: %{}}

      full = %{"val" => MapSet.new([{:p1, 3}, {:p2, 7}])}
      delta = full
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert {:p1, :p2, 10} in result
      assert {:p2, :p1, 10} in result
    end

    test "negative atom and constraint combined in multi-atom body" do
      head = %IR.Atom{relation: "safe_value", terms: [{:var, "X"}]}

      body = [
        {:positive, %IR.Atom{relation: "val", terms: [{:var, "X"}]}},
        {:negative, %IR.Atom{relation: "blocked_val", terms: [{:var, "X"}]}},
        {:constraint,
         %IR.Constraint{op: :gt, left: {:var, "X"}, right: {:const, {:int, 0}}, result: nil}}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 1, metadata: %{}}

      full = %{
        "val" => MapSet.new([{5}, {10}, {-3}]),
        "blocked_val" => MapSet.new([{10}])
      }

      delta = %{"val" => MapSet.new([{5}, {10}, {-3}])}
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert result == [{5}]
    end
  end

  describe "check_negative_atom/3 — additional coverage" do
    test "multiple matching tuples — returns false as long as one matches" do
      atom = %IR.Atom{relation: "likes", terms: [{:var, "X"}, {:var, "Y"}]}
      binding = %{"X" => :alice}
      full = %{"likes" => MapSet.new([{:alice, :pizza}, {:alice, :sushi}, {:bob, :pizza}])}

      refute Evaluator.check_negative_atom(atom, binding, full)
    end

    test "binding has all variables resolved — matches specific tuple" do
      atom = %IR.Atom{relation: "edge", terms: [{:var, "X"}, {:var, "Y"}]}
      binding = %{"X" => :a, "Y" => :b}
      full = %{"edge" => MapSet.new([{:a, :b}, {:b, :c}])}

      refute Evaluator.check_negative_atom(atom, binding, full)
    end

    test "binding does not match any tuple — returns true" do
      atom = %IR.Atom{relation: "edge", terms: [{:var, "X"}, {:var, "Y"}]}
      binding = %{"X" => :z, "Y" => :w}
      full = %{"edge" => MapSet.new([{:a, :b}, {:b, :c}])}

      assert Evaluator.check_negative_atom(atom, binding, full)
    end

    test "wildcard in negative atom matches any value" do
      atom = %IR.Atom{relation: "danger", terms: [:wildcard, :wildcard]}
      binding = %{}
      full = %{"danger" => MapSet.new([{:any, :thing}])}

      refute Evaluator.check_negative_atom(atom, binding, full)
    end

    test "wildcard in negative atom with empty relation passes" do
      atom = %IR.Atom{relation: "danger", terms: [:wildcard, :wildcard]}
      binding = %{}
      full = %{"danger" => MapSet.new()}

      assert Evaluator.check_negative_atom(atom, binding, full)
    end
  end

  describe "eval_rule_iteration/4 — type predicate constraints" do
    test "is_integer constraint filters non-integer bindings" do
      head = %IR.Atom{relation: "int_val", terms: [{:var, "X"}]}

      body = [
        {:positive, %IR.Atom{relation: "mixed", terms: [{:var, "X"}]}},
        {:constraint, %IR.Constraint{op: :is_integer, left: {:var, "X"}, right: nil, result: nil}}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 0, metadata: %{}}

      full = %{"mixed" => MapSet.new([{42}, {"hello"}])}
      delta = full
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert result == [{42}]
    end
  end

  describe "eval_rule_iteration/4 — membership constraint" do
    test "member constraint filters values not in list" do
      head = %IR.Atom{relation: "primary_color", terms: [{:var, "X"}]}

      body = [
        {:positive, %IR.Atom{relation: "color", terms: [{:var, "X"}]}},
        {:constraint,
         %IR.Constraint{
           op: :member,
           left: {:var, "X"},
           right: {:const, {:list, [{:atom, :red}, {:atom, :green}, {:atom, :blue}]}},
           result: nil
         }}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 0, metadata: %{}}

      full = %{"color" => MapSet.new([{:red}, {:yellow}, {:blue}])}
      delta = full
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert {:red} in result
      assert {:blue} in result
      refute {:yellow} in result
    end
  end

  describe "eval_rule_iteration/4 — string predicate constraints" do
    test "starts_with constraint filters bindings" do
      head = %IR.Atom{relation: "prefixed", terms: [{:var, "X"}]}

      body = [
        {:positive, %IR.Atom{relation: "name", terms: [{:var, "X"}]}},
        {:constraint,
         %IR.Constraint{
           op: :starts_with,
           left: {:var, "X"},
           right: {:const, {:str, "al"}},
           result: nil
         }}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 0, metadata: %{}}

      full = %{"name" => MapSet.new([{"alice"}, {"bob"}, {"alison"}])}
      delta = full
      old = %{}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert {"alice"} in result
      assert {"alison"} in result
      refute {"bob"} in result
    end
  end

  describe "eval_rule_iteration/4 — binary constraint with old/delta split" do
    test "two-atom body with constraint uses full/delta/old correctly" do
      head = %IR.Atom{relation: "big_salary", terms: [{:var, "X"}, {:var, "S"}]}

      body = [
        {:positive, %IR.Atom{relation: "salary", terms: [{:var, "X"}, {:var, "S"}]}},
        {:constraint,
         %IR.Constraint{op: :gt, left: {:var, "S"}, right: {:const, {:int, 100}}, result: nil}}
      ]

      rule = %IR.Rule{id: 0, head: head, body: body, stratum: 0, metadata: %{}}

      full = %{"salary" => MapSet.new([{:alice, 50}, {:bob, 150}, {:carol, 200}])}
      delta = %{"salary" => MapSet.new([{:bob, 150}, {:carol, 200}])}
      old = %{"salary" => MapSet.new([{:alice, 50}])}

      result = Evaluator.eval_rule_iteration(rule, full, delta, old)
      assert {:bob, 150} in result
      assert {:carol, 200} in result
      refute {:alice, 50} in result
    end
  end
end
