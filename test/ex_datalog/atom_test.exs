defmodule ExDatalog.AtomTest do
  use ExUnit.Case, async: true
  doctest ExDatalog.Atom

  alias ExDatalog.{Atom, Term}

  describe "new/2" do
    test "creates an atom with a relation and terms" do
      atom = Atom.new("parent", [Term.var("X"), Term.var("Y")])
      assert atom.relation == "parent"
      assert atom.terms == [{:var, "X"}, {:var, "Y"}]
    end

    test "creates an atom with constant terms" do
      atom = Atom.new("person", [Term.const(:alice)])
      assert atom.relation == "person"
      assert atom.terms == [{:const, :alice}]
    end

    test "creates an atom with a wildcard" do
      atom = Atom.new("fact", [Term.wildcard(), Term.var("X")])
      assert atom.terms == [:wildcard, {:var, "X"}]
    end

    test "creates a zero-arity atom" do
      atom = Atom.new("empty", [])
      assert atom.terms == []
    end

    test "raises on non-binary relation name" do
      assert_raise FunctionClauseError, fn ->
        Atom.new(:parent, [Term.var("X")])
      end
    end
  end

  describe "arity/1" do
    test "returns the number of terms" do
      assert Atom.arity(Atom.new("parent", [Term.var("X"), Term.var("Y")])) == 2
    end

    test "returns 1 for unary atom" do
      assert Atom.arity(Atom.new("node", [Term.const(:a)])) == 1
    end

    test "returns 0 for zero-arity atom" do
      assert Atom.arity(Atom.new("flag", [])) == 0
    end
  end

  describe "variables/1" do
    test "returns variable names from mixed terms" do
      atom = Atom.new("r", [Term.var("X"), Term.const(:alice), Term.var("Y")])
      assert Atom.variables(atom) == ["X", "Y"]
    end

    test "returns empty list when no variables" do
      atom = Atom.new("r", [Term.const(1), Term.wildcard()])
      assert Atom.variables(atom) == []
    end

    test "returns all variables in order" do
      atom = Atom.new("r", [Term.var("A"), Term.var("B")])
      assert Atom.variables(atom) == ["A", "B"]
    end
  end

  describe "valid?/1" do
    test "valid atom with variable terms" do
      assert Atom.valid?(Atom.new("parent", [Term.var("X"), Term.var("Y")])) == true
    end

    test "valid atom with const terms" do
      assert Atom.valid?(Atom.new("node", [Term.const(:a)])) == true
    end

    test "valid atom with wildcard" do
      assert Atom.valid?(Atom.new("r", [Term.wildcard()])) == true
    end

    test "valid zero-arity atom" do
      assert Atom.valid?(Atom.new("flag", [])) == true
    end

    test "invalid: empty relation name" do
      assert Atom.valid?(%Atom{relation: "", terms: [Term.var("X")]}) == false
    end

    test "invalid: bad term in list" do
      assert Atom.valid?(%Atom{relation: "r", terms: [:not_a_term]}) == false
    end

    test "invalid: non-struct" do
      assert Atom.valid?({:r, [:x]}) == false
    end

    test "invalid: nil relation" do
      assert Atom.valid?(%Atom{relation: nil, terms: []}) == false
    end
  end
end
