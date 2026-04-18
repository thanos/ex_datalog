defmodule ExDatalog.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExDatalog.{Atom, Constraint, Program, Rule, Term}

  @tag :property
  property "head variables are always a subset of rule variables" do
    check all(
            x <- StreamData.string(:alphanumeric, min_length: 1, max_length: 3),
            y <- StreamData.string(:alphanumeric, min_length: 1, max_length: 3),
            z <- StreamData.string(:alphanumeric, min_length: 1, max_length: 3)
          ) do
      rule =
        Rule.new(
          Atom.new("r", [Term.var(x), Term.var(y)]),
          [{:positive, Atom.new("s", [Term.var(x), Term.var(z)])}]
        )

      head_vars = Rule.head_variables(rule)
      all_vars = Rule.variables(rule)

      assert MapSet.subset?(MapSet.new(head_vars), MapSet.new(all_vars))
    end
  end

  @tag :property
  property "Atom.variables/1 returns only variable names" do
    check all(
            rel <- StreamData.string(:alphanumeric, min_length: 1, max_length: 8),
            terms <-
              StreamData.list_of(
                StreamData.one_of([
                  StreamData.map(
                    StreamData.string(:alphanumeric, min_length: 1, max_length: 3),
                    &Term.var/1
                  ),
                  StreamData.map(StreamData.integer(0..100), &Term.const/1),
                  StreamData.constant(Term.wildcard())
                ]),
                min_length: 1,
                max_length: 4
              )
          ) do
      atom = Atom.new(rel, terms)
      vars = Atom.variables(atom)

      for v <- vars do
        assert is_binary(v)
        assert byte_size(v) > 0
      end
    end
  end

  @tag :property
  property "Constraint constructors produce valid constraints" do
    check all(
            x <- StreamData.string(:alphanumeric, min_length: 1, max_length: 3),
            y <- StreamData.string(:alphanumeric, min_length: 1, max_length: 3),
            z <- StreamData.string(:alphanumeric, min_length: 1, max_length: 3),
            comp <- StreamData.member_of([:gt, :lt, :gte, :lte, :eq, :neq]),
            arith <- StreamData.member_of([:add, :sub, :mul, :div])
          ) do
      comparison = apply(Constraint, comp, [Term.var(x), Term.var(y)])
      arithmetic = apply(Constraint, arith, [Term.var(x), Term.var(y), Term.var(z)])

      assert Constraint.comparison?(comparison)
      assert not Constraint.arithmetic?(comparison)
      assert Constraint.valid?(comparison)

      assert Constraint.arithmetic?(arithmetic)
      assert not Constraint.comparison?(arithmetic)
      assert Constraint.valid?(arithmetic)
    end
  end

  @tag :property
  property "a well-formed program always passes validation" do
    check all(
            names <-
              StreamData.list_of(
                StreamData.string(:alphanumeric, min_length: 1, max_length: 8),
                min_length: 2,
                max_length: 5
              )
          ) do
      unique_names = names |> Enum.uniq() |> Enum.take(4)

      program =
        Enum.reduce(unique_names, Program.new(), fn name, acc ->
          Program.add_relation(acc, name, [:atom, :atom])
        end)

      assert {:ok, _} = ExDatalog.validate(program)
    end
  end

  @tag :property
  property "adding a duplicate relation always returns an error" do
    check all(name <- StreamData.string(:alphanumeric, min_length: 1, max_length: 8)) do
      program = Program.new() |> Program.add_relation(name, [:atom])
      assert {:error, _} = Program.add_relation(program, name, [:atom])
    end
  end

  @tag :property
  property "Term.var, Term.const, and Term.wildcard always produce valid terms" do
    check all(
            name <- StreamData.string(:alphanumeric, min_length: 1, max_length: 5),
            int <- StreamData.integer(),
            atom <- StreamData.atom(:alphanumeric)
          ) do
      assert Term.valid?(Term.var(name))
      assert Term.valid?(Term.const(int))
      assert Term.valid?(Term.const(atom))
      assert Term.valid?(Term.wildcard())
    end
  end

  @tag :property
  property "strata assignment gives stratum 0 to EDB-only relations" do
    check all(
            names <-
              StreamData.uniq_list_of(
                StreamData.string(:alphanumeric, min_length: 1, max_length: 5),
                min_length: 2,
                max_length: 5
              )
          ) do
      alias ExDatalog.Validator.Stratification

      [edb_name, idb_name | _] = names

      program =
        Program.new()
        |> Program.add_relation(edb_name, [:atom])
        |> Program.add_relation(idb_name, [:atom])
        |> Program.add_rule(
          Rule.new(
            Atom.new(idb_name, [Term.var("X")]),
            [{:positive, Atom.new(edb_name, [Term.var("X")])}]
          )
        )

      strata = Stratification.assign_strata(program)
      assert strata[edb_name] == 0
    end
  end

  @tag :property
  property "Constraint.arithmetic?/1 and comparison?/1 are mutually exclusive" do
    check all(
            op <- StreamData.member_of([:gt, :lt, :gte, :lte, :eq, :neq, :add, :sub, :mul, :div])
          ) do
      assert Constraint.arithmetic?(%Constraint{
               op: op,
               left: Term.var("X"),
               right: Term.const(0),
               result: nil
             }) !=
               Constraint.comparison?(%Constraint{
                 op: op,
                 left: Term.var("X"),
                 right: Term.const(0),
                 result: nil
               })
    end
  end
end
