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

  After compilation, the IR is validated against structural invariants:
  unique rule IDs, stratum bounds, rule-in-stratum consistency, and
  relation reference integrity. Violations raise an error — these indicate
  a bug in the compiler, not an invalid program (programs are validated
  before compilation).

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
    # The builder stores facts/rules in prepend order (newest first) for O(1)
    # per-call cost. Normalize to insertion order (oldest first) so that
    # with_index assigns deterministic rule IDs (rule 0 = first rule added).
    program = %{
      program
      | facts: Enum.reverse(program.facts),
        rules: Enum.reverse(program.rules)
    }

    rule_strata = Stratifier.assign(program)
    strata = Stratifier.compute_strata(program)

    relations = compile_relations(program)
    facts = compile_facts(program)
    rules = compile_rules(program, rule_strata)

    ir = %IR{
      relations: relations,
      facts: facts,
      rules: rules,
      strata: strata
    }

    :ok = validate_ir!(ir)
    ir
  end

  defp validate_ir!(%IR{rules: rules, strata: strata, relations: relations, facts: facts}) do
    rule_ids = Enum.map(rules, & &1.id)
    relation_names = MapSet.new(relations, & &1.name)
    fact_relations = MapSet.new(facts, & &1.relation)
    head_relations = MapSet.new(rules, & &1.head.relation)

    rule_id_uniqueness!(rule_ids)
    stratum_bounds!(rules, strata)
    rule_in_stratum_consistency!(rules, strata)
    relation_references!(fact_relations, head_relations, relation_names)

    :ok
  end

  defp rule_id_uniqueness!(rule_ids) do
    duplicate_ids = rule_ids -- Enum.uniq(rule_ids)

    unless duplicate_ids == [] do
      raise "IR validation failed: duplicate rule IDs: #{inspect(Enum.uniq(duplicate_ids))}"
    end
  end

  defp stratum_bounds!(rules, strata) do
    max_stratum =
      case strata do
        [] -> -1
        _ -> strata |> Enum.map(& &1.index) |> Enum.max()
      end

    out_of_bounds =
      Enum.filter(rules, fn rule -> rule.stratum < 0 or rule.stratum > max_stratum end)

    unless out_of_bounds == [] do
      raise "IR validation failed: rules with stratum out of bounds [0..#{max_stratum}]: #{inspect(Enum.map(out_of_bounds, & &1.id))}"
    end
  end

  defp rule_in_stratum_consistency!(rules, strata) do
    rule_ids = MapSet.new(rules, & &1.id)
    stratum_rule_ids = strata |> Enum.flat_map(& &1.rule_ids) |> MapSet.new()

    missing_from_strata = MapSet.difference(rule_ids, stratum_rule_ids)
    extra_in_strata = MapSet.difference(stratum_rule_ids, rule_ids)

    unless MapSet.size(missing_from_strata) == 0 do
      raise "IR validation failed: rules not in any stratum: #{inspect(MapSet.to_list(missing_from_strata))}"
    end

    unless MapSet.size(extra_in_strata) == 0 do
      raise "IR validation failed: strata reference non-existent rule IDs: #{inspect(MapSet.to_list(extra_in_strata))}"
    end
  end

  defp relation_references!(fact_relations, head_relations, declared_relations) do
    undeclared_facts = MapSet.difference(fact_relations, declared_relations)
    undeclared_heads = MapSet.difference(head_relations, declared_relations)

    unless MapSet.size(undeclared_facts) == 0 do
      raise "IR validation failed: facts reference undeclared relations: #{inspect(MapSet.to_list(undeclared_facts))}"
    end

    unless MapSet.size(undeclared_heads) == 0 do
      raise "IR validation failed: rule heads reference undeclared relations: #{inspect(MapSet.to_list(undeclared_heads))}"
    end
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
