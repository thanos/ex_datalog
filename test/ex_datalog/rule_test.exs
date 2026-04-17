defmodule ExDatalog.RuleTest do
  use ExUnit.Case, async: true
  doctest ExDatalog.Rule

  alias ExDatalog.{Rule, Atom, Term, Constraint}

  defp parent_atom(x, y), do: Atom.new("parent", [Term.var(x), Term.var(y)])
  defp ancestor_atom(x, y), do: Atom.new("ancestor", [Term.var(x), Term.var(y)])
  defp person_atom(x), do: Atom.new("person", [Term.var(x)])

  describe "new/2 and new/3" do
    test "creates a rule with head and body" do
      head = ancestor_atom("X", "Y")
      body = [{:positive, parent_atom("X", "Y")}]
      rule = Rule.new(head, body)

      assert rule.head == head
      assert rule.body == body
      assert rule.constraints == []
    end

    test "creates a rule with constraints" do
      head = Atom.new("adult", [Term.var("X")])

      body = [
        {:positive, Atom.new("person", [Term.var("X")])},
        {:positive, Atom.new("age", [Term.var("X"), Term.var("A")])}
      ]

      constraints = [Constraint.gte(Term.var("A"), Term.const(18))]
      rule = Rule.new(head, body, constraints)

      assert rule.constraints == constraints
    end

    test "creates a rule with empty body" do
      head = Atom.new("axiom", [Term.const(:truth)])
      rule = Rule.new(head, [])
      assert rule.body == []
    end

    test "creates a rule with negation" do
      head = Atom.new("bachelor", [Term.var("X")])

      body = [
        {:positive, person_atom("X")},
        {:negative, Atom.new("married", [Term.var("X"), Term.wildcard()])}
      ]

      rule = Rule.new(head, body)
      assert length(rule.body) == 2
    end
  end

  describe "variables/1" do
    test "returns all unique variables across head and body" do
      head = ancestor_atom("X", "Z")

      body = [
        {:positive, parent_atom("X", "Y")},
        {:positive, ancestor_atom("Y", "Z")}
      ]

      rule = Rule.new(head, body)
      assert Rule.variables(rule) |> Enum.sort() == ["X", "Y", "Z"]
    end

    test "includes variables from negative body atoms" do
      head = Atom.new("r", [Term.var("X")])

      body = [
        {:positive, Atom.new("a", [Term.var("X")])},
        {:negative, Atom.new("b", [Term.var("Y")])}
      ]

      rule = Rule.new(head, body)
      assert Rule.variables(rule) |> Enum.sort() == ["X", "Y"]
    end

    test "includes constraint input and result variables" do
      head = Atom.new("result", [Term.var("Z")])
      body = [{:positive, Atom.new("data", [Term.var("X"), Term.var("Y")])}]
      constraints = [Constraint.add(Term.var("X"), Term.var("Y"), Term.var("Z"))]
      rule = Rule.new(head, body, constraints)
      assert Rule.variables(rule) |> Enum.sort() == ["X", "Y", "Z"]
    end

    test "deduplicates variables appearing in multiple atoms" do
      head = ancestor_atom("X", "Z")

      body = [
        {:positive, parent_atom("X", "Y")},
        {:positive, ancestor_atom("Y", "Z")}
      ]

      vars = Rule.variables(Rule.new(head, body))
      assert length(vars) == length(Enum.uniq(vars))
    end
  end

  describe "head_variables/1" do
    test "returns variables from the head atom only" do
      head = ancestor_atom("X", "Z")
      body = [{:positive, parent_atom("X", "Y")}]
      assert Rule.head_variables(Rule.new(head, body)) == ["X", "Z"]
    end
  end

  describe "positive_body_variables/1" do
    test "returns variables from positive body atoms only" do
      head = Atom.new("result", [Term.var("X")])

      body = [
        {:positive, Atom.new("a", [Term.var("X"), Term.var("Y")])},
        {:negative, Atom.new("b", [Term.var("Z")])}
      ]

      result = Rule.positive_body_variables(Rule.new(head, body))
      assert Enum.sort(result) == ["X", "Y"]
      refute "Z" in result
    end

    test "deduplicates across multiple positive atoms" do
      head = ancestor_atom("X", "Z")

      body = [
        {:positive, parent_atom("X", "Y")},
        {:positive, ancestor_atom("Y", "Z")}
      ]

      vars = Rule.positive_body_variables(Rule.new(head, body))
      assert length(vars) == length(Enum.uniq(vars))
    end
  end

  describe "body_atoms/1" do
    test "strips polarity and returns atoms" do
      a1 = parent_atom("X", "Y")
      a2 = person_atom("X")
      body = [{:positive, a1}, {:negative, a2}]
      rule = Rule.new(ancestor_atom("X", "Y"), body)
      assert Rule.body_atoms(rule) == [a1, a2]
    end

    test "returns empty list for empty body" do
      rule = Rule.new(Atom.new("axiom", []), [])
      assert Rule.body_atoms(rule) == []
    end
  end

  describe "has_negation?/1" do
    test "returns true when body contains a negative literal" do
      head = Atom.new("bachelor", [Term.var("X")])

      body = [
        {:positive, person_atom("X")},
        {:negative, Atom.new("married", [Term.var("X"), Term.wildcard()])}
      ]

      assert Rule.has_negation?(Rule.new(head, body)) == true
    end

    test "returns false when all body literals are positive" do
      head = ancestor_atom("X", "Y")
      body = [{:positive, parent_atom("X", "Y")}]
      assert Rule.has_negation?(Rule.new(head, body)) == false
    end

    test "returns false for empty body" do
      rule = Rule.new(Atom.new("axiom", []), [])
      assert Rule.has_negation?(rule) == false
    end
  end
end
