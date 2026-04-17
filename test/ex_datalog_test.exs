defmodule ExDatalogTest do
  use ExUnit.Case, async: true
  doctest ExDatalog

  alias ExDatalog.{Program, Rule, Atom, Term}

  describe "new/0" do
    test "delegates to Program.new/0" do
      assert ExDatalog.new() == Program.new()
    end
  end

  describe "validate/1" do
    test "returns ok for a structurally valid program" do
      program =
        Program.new()
        |> Program.add_relation("edge", [:atom, :atom])
        |> Program.add_fact("edge", [:a, :b])

      assert {:ok, _} = ExDatalog.validate(program)
    end

    test "returns error for a program with a rule referencing an undefined relation" do
      # Build a program where the rule body references an undefined relation
      # by bypassing the builder's structural check (inject directly).
      program = %Program{
        relations: %{"a" => %{arity: 1, types: [:atom]}},
        facts: [],
        rules: [
          Rule.new(
            Atom.new("a", [Term.var("X")]),
            [{:positive, Atom.new("undefined_rel", [Term.var("X")])}]
          )
        ]
      }

      assert {:error, errors} = ExDatalog.validate(program)
      assert length(errors) > 0
      assert Enum.any?(errors, &(&1.kind == :undefined_relation))
    end
  end
end
