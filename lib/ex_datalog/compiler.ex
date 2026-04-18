defmodule ExDatalog.Compiler do
  @moduledoc """
  Compiles a validated `ExDatalog.Program` into an `ExDatalog.IR` program.

  The compiler transforms the high-level AST (rules, atoms, terms, constraints)
  into a deterministic, engine-neutral intermediate representation suitable
  for evaluation by any backend that implements `ExDatalog.Engine`.

  ## Compilation steps

  1. **Validate** — calls `ExDatalog.Validator.validate/1` to ensure the
    program is structurally and semantically correct.

  2. **Assign strata** — uses `ExDatalog.Compiler.Stratifier` to determine
    which stratum each rule belongs to.

  3. **Canonicalize** — sorts relations, facts, and rules into deterministic
    order. Rule IDs are assigned monotonically in canonical order.

  4. **Convert** — transforms AST types (`Term`, `Atom`, `Constraint`) into
    IR types (`IRTerm`, `IRAtom`, `IRConstraint`), replacing `{:const, value}`
    with tagged IR values (`{:const, {:int, n}}`, `{:const, {:atom, a}}`, etc.).

  The output is a `%ExDatalog.IR{}` struct that is deterministic for a given
  input program: compiling the same program twice produces identical IR.

  ## Examples

      iex> alias ExDatalog.{Program, Rule, Atom, Term, Compiler}
      iex> program =
      ...>   Program.new()
      ...>   |> Program.add_relation("parent", [:atom, :atom])
      ...>   |> Program.add_relation("ancestor", [:atom, :atom])
      ...>   |> Program.add_fact("parent", [:alice, :bob])
      ...>   |> Program.add_rule(
      ...>     Rule.new(
      ...>       Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
      ...>       [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
      ...>     )
      ...>   )
      iex> {:ok, ir} = Compiler.compile(program)
      iex> length(ir.rules) == 1 and length(ir.relations) == 2
      true

  """

  alias ExDatalog.{Compiler.Stratifier, IR, Program}

  @doc """
  Compiles a program into its IR representation.

  Returns `{:ok, %ExDatalog.IR{}}` on success, or `{:error, errors}` if
  validation fails.
  """
  @spec compile(Program.t()) :: {:ok, IR.t()} | {:error, [ExDatalog.Validator.Error.t()]}
  def compile(%Program{} = program) do
    case ExDatalog.validate(program) do
      {:ok, validated} -> {:ok, do_compile(validated)}
      {:error, errors} -> {:error, errors}
    end
  end

  defp do_compile(program) do
    rule_strata = Stratifier.assign(program)
    strata = Stratifier.compute_strata(program)

    relations = compile_relations(program)
    facts = compile_facts(program)
    rules = compile_rules(program, rule_strata)

    %IR{
      relations: relations,
      facts: facts,
      rules: rules,
      strata: strata
    }
  end

  defp compile_relations(%Program{relations: rels}) do
    rels
    |> Enum.sort_by(fn {name, _schema} -> name end)
    |> Enum.map(fn {name, %{arity: arity, types: types}} ->
      %IR.Relation{name: name, arity: arity, types: types}
    end)
  end

  defp compile_facts(%Program{facts: facts}) do
    facts
    |> Enum.sort_by(fn {relation, values} -> {relation, values} end)
    |> Enum.map(fn {relation, values} ->
      %IR.Fact{relation: relation, values: Enum.map(values, &compile_value/1)}
    end)
  end

  defp compile_rules(%Program{rules: rules}, rule_strata) do
    rules
    |> Enum.with_index()
    |> Enum.sort_by(fn {rule, idx} ->
      stratum = Map.get(rule_strata, idx, 0)
      {stratum, rule.head.relation, idx}
    end)
    |> Enum.with_index(fn {rule, orig_idx}, new_idx ->
      stratum = Map.get(rule_strata, orig_idx, 0)
      compile_rule(rule, new_idx, stratum)
    end)
  end

  defp compile_rule(
         %ExDatalog.Rule{head: head, body: body, constraints: constraints},
         id,
         stratum
       ) do
    ir_head = IR.from_atom(head)

    ir_body =
      Enum.map(body, fn
        {:positive, %ExDatalog.Atom{} = atom} -> {:positive, IR.from_atom(atom)}
        {:negative, %ExDatalog.Atom{} = atom} -> {:negative, IR.from_atom(atom)}
      end)

    ir_constraints = Enum.map(constraints, fn c -> {:constraint, IR.from_constraint(c)} end)

    %IR.Rule{
      id: id,
      head: ir_head,
      body: ir_body ++ ir_constraints,
      stratum: stratum,
      metadata: %{}
    }
  end

  defp compile_value(value) when is_integer(value), do: {:int, value}
  defp compile_value(value) when is_binary(value), do: {:str, value}
  defp compile_value(value) when is_atom(value), do: {:atom, value}
end
