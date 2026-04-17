defmodule ExDatalog.TermTest do
  use ExUnit.Case, async: true
  doctest ExDatalog.Term

  alias ExDatalog.Term

  describe "var/1" do
    test "creates a variable term" do
      assert Term.var("X") == {:var, "X"}
    end

    test "accepts multi-character names" do
      assert Term.var("ParentNode") == {:var, "ParentNode"}
    end

    test "raises on non-binary name" do
      assert_raise FunctionClauseError, fn -> Term.var(:x) end
    end

    test "raises on empty string" do
      assert_raise FunctionClauseError, fn -> Term.var("") end
    end
  end

  describe "const/1" do
    test "creates a constant from an atom" do
      assert Term.const(:alice) == {:const, :alice}
    end

    test "creates a constant from an integer" do
      assert Term.const(42) == {:const, 42}
    end

    test "creates a constant from a string" do
      assert Term.const("hello") == {:const, "hello"}
    end

    test "raises on float" do
      assert_raise FunctionClauseError, fn -> Term.const(1.5) end
    end

    test "raises on list" do
      assert_raise FunctionClauseError, fn -> Term.const([1, 2]) end
    end
  end

  describe "wildcard/0" do
    test "returns :wildcard" do
      assert Term.wildcard() == :wildcard
    end
  end

  describe "var?/1" do
    test "returns true for var term" do
      assert Term.var?({:var, "X"}) == true
    end

    test "returns false for const term" do
      assert Term.var?({:const, :alice}) == false
    end

    test "returns false for wildcard" do
      assert Term.var?(:wildcard) == false
    end

    test "returns false for random value" do
      assert Term.var?(:foo) == false
    end
  end

  describe "const?/1" do
    test "returns true for const term" do
      assert Term.const?({:const, :alice}) == true
    end

    test "returns false for var term" do
      assert Term.const?({:var, "X"}) == false
    end

    test "returns false for wildcard" do
      assert Term.const?(:wildcard) == false
    end
  end

  describe "wildcard?/1" do
    test "returns true for wildcard" do
      assert Term.wildcard?(:wildcard) == true
    end

    test "returns false for var" do
      assert Term.wildcard?({:var, "X"}) == false
    end

    test "returns false for const" do
      assert Term.wildcard?({:const, :alice}) == false
    end
  end

  describe "valid?/1" do
    test "accepts valid var" do
      assert Term.valid?({:var, "X"}) == true
    end

    test "accepts valid integer const" do
      assert Term.valid?({:const, 1}) == true
    end

    test "accepts valid string const" do
      assert Term.valid?({:const, "hello"}) == true
    end

    test "accepts valid atom const" do
      assert Term.valid?({:const, :alice}) == true
    end

    test "accepts wildcard" do
      assert Term.valid?(:wildcard) == true
    end

    test "rejects var with empty name" do
      assert Term.valid?({:var, ""}) == false
    end

    test "rejects var with non-binary name" do
      assert Term.valid?({:var, :x}) == false
    end

    test "rejects const with float value" do
      assert Term.valid?({:const, 1.0}) == false
    end

    test "rejects unknown atom" do
      assert Term.valid?(:bad) == false
    end

    test "rejects random tuple" do
      assert Term.valid?({:foo, "bar"}) == false
    end

    test "rejects nil" do
      assert Term.valid?(nil) == false
    end
  end

  describe "variables/1" do
    test "extracts variable names from a mixed list" do
      terms = [Term.var("X"), Term.const(:alice), Term.var("Y"), Term.wildcard()]
      assert Term.variables(terms) == ["X", "Y"]
    end

    test "returns empty list for no variables" do
      terms = [Term.const(1), Term.wildcard(), Term.const(:alice)]
      assert Term.variables(terms) == []
    end

    test "returns all vars in order" do
      terms = [Term.var("A"), Term.var("B"), Term.var("C")]
      assert Term.variables(terms) == ["A", "B", "C"]
    end

    test "returns empty list for empty input" do
      assert Term.variables([]) == []
    end
  end
end
