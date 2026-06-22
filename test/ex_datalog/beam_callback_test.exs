defmodule ExDatalog.BeamCallbackTest do
  use ExUnit.Case, async: true

  alias ExDatalog.{Atom, Callback, Knowledge, Program, Rule, Term}

  doctest ExDatalog.Callback

  defmodule Predicates do
    @moduledoc false
    def adult?(age), do: age >= 18
    def valid_email?(email), do: String.contains?(email, "@")
    def double(x), do: x * 2
    def boom(_x), do: raise("callback exploded")
    def slow(_x), do: Process.sleep(500) && true
  end

  describe "boolean callback (builder API)" do
    test "filters bindings by predicate result" do
      program =
        Program.new()
        |> Program.add_relation("person", [:atom, :integer])
        |> Program.add_relation("adult", [:atom])
        |> Program.add_fact("person", [:alice, 25])
        |> Program.add_fact("person", [:bob, 12])
        |> Program.add_rule(
          Rule.new(
            Atom.new("adult", [Term.var("Name")]),
            [
              {:positive, Atom.new("person", [Term.var("Name"), Term.var("Age")])},
              {:callback, Callback.new(Predicates, :adult?, [Term.var("Age")])}
            ]
          )
        )

      {:ok, knowledge} = ExDatalog.materialize(program)
      result = Knowledge.get(knowledge, "adult")
      assert MapSet.size(result) == 1
      assert {:alice} in result
    end
  end

  describe "value-returning callback" do
    test "binds the result variable" do
      program =
        Program.new()
        |> Program.add_relation("num", [:integer])
        |> Program.add_relation("doubled", [:integer, :integer])
        |> Program.add_fact("num", [3])
        |> Program.add_fact("num", [5])
        |> Program.add_rule(
          Rule.new(
            Atom.new("doubled", [Term.var("X"), Term.var("Y")]),
            [
              {:positive, Atom.new("num", [Term.var("X")])},
              {:callback, Callback.new(Predicates, :double, [Term.var("X")], Term.var("Y"))}
            ]
          )
        )

      {:ok, knowledge} = ExDatalog.materialize(program)
      result = Knowledge.get(knowledge, "doubled")
      assert {3, 6} in result
      assert {5, 10} in result
    end
  end

  describe "exception and timeout isolation" do
    test "a raising callback filters the binding" do
      program =
        Program.new()
        |> Program.add_relation("num", [:integer])
        |> Program.add_relation("ok", [:integer])
        |> Program.add_fact("num", [1])
        |> Program.add_rule(
          Rule.new(
            Atom.new("ok", [Term.var("X")]),
            [
              {:positive, Atom.new("num", [Term.var("X")])},
              {:callback, Callback.new(Predicates, :boom, [Term.var("X")])}
            ]
          )
        )

      {:ok, knowledge} = ExDatalog.materialize(program)
      assert MapSet.size(Knowledge.get(knowledge, "ok")) == 0
    end

    test "a slow callback is filtered by the timeout" do
      program =
        Program.new()
        |> Program.add_relation("num", [:integer])
        |> Program.add_relation("ok", [:integer])
        |> Program.add_fact("num", [1])
        |> Program.add_rule(
          Rule.new(
            Atom.new("ok", [Term.var("X")]),
            [
              {:positive, Atom.new("num", [Term.var("X")])},
              {:callback, Callback.new(Predicates, :slow, [Term.var("X")])}
            ]
          )
        )

      {:ok, knowledge} = ExDatalog.materialize(program, callback_timeout_ms: 50)
      assert MapSet.size(Knowledge.get(knowledge, "ok")) == 0
    end
  end

  describe "validation" do
    test "rejects a callback referencing a missing function" do
      program =
        Program.new()
        |> Program.add_relation("num", [:integer])
        |> Program.add_relation("ok", [:integer])
        |> Program.add_fact("num", [1])
        |> Program.add_rule(
          Rule.new(
            Atom.new("ok", [Term.var("X")]),
            [
              {:positive, Atom.new("num", [Term.var("X")])},
              {:callback, Callback.new(Predicates, :nonexistent, [Term.var("X")])}
            ]
          )
        )

      assert {:error, errors} = ExDatalog.materialize(program)
      assert Enum.any?(errors, fn e -> e.kind == :invalid_callback end)
    end

    test "rejects a callback with an unbound input variable" do
      program =
        Program.new()
        |> Program.add_relation("num", [:integer])
        |> Program.add_relation("ok", [:integer])
        |> Program.add_fact("num", [1])
        |> Program.add_rule(
          Rule.new(
            Atom.new("ok", [Term.var("X")]),
            [
              {:positive, Atom.new("num", [Term.var("X")])},
              {:callback, Callback.new(Predicates, :adult?, [Term.var("Z")])}
            ]
          )
        )

      assert {:error, errors} = ExDatalog.materialize(program)
      assert Enum.any?(errors, fn e -> e.kind == :unbound_constraint_variable end)
    end
  end

  describe "DSL predicate macro" do
    test "boolean predicate in a rule body" do
      defmodule AdultSchema do
        use ExDatalog.Schema

        relation :person do
          field(:name, :atom)
          field(:age, :integer)
        end

        relation :adult do
          field(:name, :atom)
        end

        predicate(:adult?, ExDatalog.BeamCallbackTest.Predicates, :adult?, [:integer], :boolean)

        fact(person(:alice, 30))
        fact(person(:bob, 10))

        rule adult(Name) do
          person(Name, Age)
          adult?(Age)
        end
      end

      {:ok, knowledge} = AdultSchema.materialize()
      result = Knowledge.get(knowledge, "adult")
      assert {:alice} in result
      refute {:bob} in result
    end

    test "value predicate binds the last argument" do
      defmodule DoubleSchema do
        use ExDatalog.Schema

        relation :num do
          field(:x, :integer)
        end

        relation :doubled do
          field(:x, :integer)
          field(:y, :integer)
        end

        predicate(:double, ExDatalog.BeamCallbackTest.Predicates, :double, [:integer], :value)

        fact(num(4))

        rule doubled(X, Y) do
          num(X)
          double(X, Y)
        end
      end

      {:ok, knowledge} = DoubleSchema.materialize()
      assert {4, 8} in Knowledge.get(knowledge, "doubled")
    end
  end
end
