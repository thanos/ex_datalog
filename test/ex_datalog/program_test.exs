defmodule ExDatalog.ProgramTest do
  use ExUnit.Case, async: true
  doctest ExDatalog.Program

  alias ExDatalog.{Atom, Program, Rule, Term}

  defp base_program do
    Program.new()
    |> Program.add_relation("parent", [:atom, :atom])
    |> Program.add_relation("ancestor", [:atom, :atom])
  end

  defp parent_rule do
    Rule.new(
      Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
      [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
    )
  end

  describe "new/0" do
    test "creates an empty program" do
      program = Program.new()
      assert program.relations == %{}
      assert program.facts == []
      assert program.rules == []
    end
  end

  describe "add_relation/3" do
    test "adds a relation with type schema" do
      program = Program.new() |> Program.add_relation("parent", [:atom, :atom])
      assert Map.has_key?(program.relations, "parent")
      assert program.relations["parent"] == %{arity: 2, types: [:atom, :atom]}
    end

    test "arity is inferred from types list" do
      program = Program.new() |> Program.add_relation("triple", [:atom, :integer, :string])
      assert program.relations["triple"].arity == 3
    end

    test "supports :any type" do
      program = Program.new() |> Program.add_relation("r", [:any])
      assert program.relations["r"].types == [:any]
    end

    test "multiple relations can be added" do
      program =
        Program.new()
        |> Program.add_relation("a", [:atom])
        |> Program.add_relation("b", [:integer, :integer])

      assert Map.keys(program.relations) |> Enum.sort() == ["a", "b"]
    end

    test "returns error for empty relation name" do
      assert {:error, _} = Program.add_relation(Program.new(), "", [:atom])
    end

    test "returns error for empty types list" do
      assert {:error, _} = Program.add_relation(Program.new(), "r", [])
    end

    test "returns error for duplicate relation" do
      program = Program.new() |> Program.add_relation("parent", [:atom, :atom])
      assert {:error, msg} = Program.add_relation(program, "parent", [:atom])
      assert msg =~ "already defined"
    end
  end

  describe "add_fact/3" do
    test "adds a fact to an existing relation" do
      program = base_program() |> Program.add_fact("parent", [:alice, :bob])
      assert program.facts == [{"parent", [:alice, :bob]}]
    end

    test "multiple facts accumulate; builder stores newest-first" do
      program =
        base_program()
        |> Program.add_fact("parent", [:alice, :bob])
        |> Program.add_fact("parent", [:bob, :carol])

      # The builder prepends for O(1) per-call cost; the struct stores
      # facts newest-first. validate/1 does NOT reorder the struct —
      # normalization happens inside the compiler.
      assert length(program.facts) == 2
      assert {"parent", [:alice, :bob]} in program.facts
      assert {"parent", [:bob, :carol]} in program.facts
    end

    test "facts for different relations can coexist" do
      program =
        base_program()
        |> Program.add_fact("parent", [:alice, :bob])
        |> Program.add_fact("ancestor", [:alice, :carol])

      assert length(program.facts) == 2
    end

    test "returns error for undefined relation" do
      assert {:error, msg} = Program.add_fact(Program.new(), "unknown", [:alice])
      assert msg =~ "not defined"
    end

    test "returns error for arity mismatch (too few)" do
      program = base_program()
      assert {:error, msg} = Program.add_fact(program, "parent", [:alice])
      assert msg =~ "arity mismatch"
    end

    test "returns error for arity mismatch (too many)" do
      program = base_program()
      assert {:error, msg} = Program.add_fact(program, "parent", [:alice, :bob, :carol])
      assert msg =~ "arity mismatch"
    end

    test "accepts integer values" do
      program = Program.new() |> Program.add_relation("age", [:atom, :integer])
      program = Program.add_fact(program, "age", [:alice, 30])
      assert program.facts == [{"age", [:alice, 30]}]
    end

    test "accepts string values" do
      program = Program.new() |> Program.add_relation("label", [:string])
      program = Program.add_fact(program, "label", ["hello"])
      assert program.facts == [{"label", ["hello"]}]
    end
  end

  describe "add_rule/2" do
    test "adds a structurally valid rule" do
      program = base_program() |> Program.add_rule(parent_rule())
      assert length(program.rules) == 1
    end

    test "multiple rules accumulate in insertion order" do
      rule2 =
        Rule.new(
          Atom.new("ancestor", [Term.var("X"), Term.var("Z")]),
          [
            {:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])},
            {:positive, Atom.new("ancestor", [Term.var("Y"), Term.var("Z")])}
          ]
        )

      program = base_program() |> Program.add_rule(parent_rule()) |> Program.add_rule(rule2)
      assert length(program.rules) == 2
    end

    test "returns error when head references undefined relation" do
      bad_rule =
        Rule.new(
          Atom.new("undefined_rel", [Term.var("X")]),
          [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
        )

      assert {:error, msg} =
               Program.new()
               |> Program.add_relation("parent", [:atom, :atom])
               |> Program.add_rule(bad_rule)

      assert msg =~ "undefined relation"
    end

    test "returns error when body atom references undefined relation" do
      bad_rule =
        Rule.new(
          Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
          [{:positive, Atom.new("nonexistent", [Term.var("X"), Term.var("Y")])}]
        )

      assert {:error, msg} = base_program() |> Program.add_rule(bad_rule)
      assert msg =~ "undefined relation"
    end

    test "returns error when head arity mismatches schema" do
      bad_rule =
        Rule.new(
          Atom.new("parent", [Term.var("X")]),
          [{:positive, Atom.new("ancestor", [Term.var("X"), Term.var("Y")])}]
        )

      assert {:error, msg} = base_program() |> Program.add_rule(bad_rule)
      assert msg =~ "arity mismatch"
    end

    test "returns error when body atom arity mismatches schema" do
      bad_rule =
        Rule.new(
          Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
          [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y"), Term.var("Z")])}]
        )

      assert {:error, msg} = base_program() |> Program.add_rule(bad_rule)
      assert msg =~ "arity mismatch"
    end

    test "accepts rules with negative body literals" do
      program =
        Program.new()
        |> Program.add_relation("person", [:atom])
        |> Program.add_relation("married", [:atom, :atom])
        |> Program.add_relation("bachelor", [:atom])

      rule =
        Rule.new(
          Atom.new("bachelor", [Term.var("X")]),
          [
            {:positive, Atom.new("person", [Term.var("X")])},
            {:negative, Atom.new("married", [Term.var("X"), Term.wildcard()])}
          ]
        )

      result = Program.add_rule(program, rule)
      assert length(result.rules) == 1
    end

    test "accepts rules with wildcards in body" do
      program =
        Program.new()
        |> Program.add_relation("edge", [:atom, :atom])
        |> Program.add_relation("has_child", [:atom])

      rule =
        Rule.new(
          Atom.new("has_child", [Term.var("X")]),
          [{:positive, Atom.new("edge", [Term.var("X"), Term.wildcard()])}]
        )

      result = Program.add_rule(program, rule)
      assert length(result.rules) == 1
    end
  end

  describe "relation/2" do
    test "returns the schema for a defined relation" do
      program = base_program()
      assert Program.relation(program, "parent") == %{arity: 2, types: [:atom, :atom]}
    end

    test "returns nil for undefined relation" do
      assert Program.relation(Program.new(), "unknown") == nil
    end
  end

  describe "has_relation?/2" do
    test "returns true for defined relation" do
      program = base_program()
      assert Program.has_relation?(program, "parent") == true
    end

    test "returns false for undefined relation" do
      assert Program.has_relation?(Program.new(), "unknown") == false
    end
  end

  describe "pipeline chaining" do
    test "full program construction pipeline" do
      program =
        Program.new()
        |> Program.add_relation("parent", [:atom, :atom])
        |> Program.add_relation("ancestor", [:atom, :atom])
        |> Program.add_fact("parent", [:alice, :bob])
        |> Program.add_fact("parent", [:bob, :carol])
        |> Program.add_rule(parent_rule())

      assert map_size(program.relations) == 2
      assert length(program.facts) == 2
      assert length(program.rules) == 1
    end

    test "add_relation error propagates through add_fact pipeline" do
      result =
        Program.new()
        |> Program.add_relation("", [:atom])
        |> Program.add_fact("parent", [:alice, :bob])

      assert {:error, msg} = result
      assert msg =~ "non-empty string"
    end

    test "add_relation error propagates through add_rule pipeline" do
      result =
        Program.new()
        |> Program.add_relation("", [:atom])
        |> Program.add_rule(parent_rule())

      assert {:error, msg} = result
      assert msg =~ "non-empty string"
    end

    test "add_fact error propagates through add_rule pipeline" do
      result =
        Program.new()
        |> Program.add_relation("parent", [:atom, :atom])
        |> Program.add_fact("unknown", [:alice])
        |> Program.add_rule(parent_rule())

      assert {:error, msg} = result
      assert msg =~ "not defined"
    end

    test "add_relation duplicate error propagates through full pipeline" do
      result =
        Program.new()
        |> Program.add_relation("parent", [:atom, :atom])
        |> Program.add_relation("parent", [:atom])
        |> Program.add_fact("parent", [:alice, :bob])
        |> Program.add_rule(parent_rule())

      assert {:error, msg} = result
      assert msg =~ "already defined"
    end

    test "add_fact arity error propagates through add_rule" do
      result =
        Program.new()
        |> Program.add_relation("parent", [:atom, :atom])
        |> Program.add_relation("ancestor", [:atom, :atom])
        |> Program.add_fact("parent", [:alice])
        |> Program.add_rule(parent_rule())

      assert {:error, msg} = result
      assert msg =~ "arity mismatch"
    end

    test "add_rule error does not lose original error when piped further" do
      result =
        Program.new()
        |> Program.add_relation("parent", [:atom, :atom])
        |> Program.add_fact("nonexistent", [:alice])
        |> Program.add_fact("parent", [:alice, :bob])

      assert {:error, msg} = result
      assert msg =~ "not defined"
    end
  end
end
