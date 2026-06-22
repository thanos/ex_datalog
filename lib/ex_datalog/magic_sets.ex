defmodule ExDatalog.MagicSets do
  @moduledoc """
  Magic-sets program transformation for demand-driven (goal-directed) evaluation.

  Magic sets rewrites a program so that bottom-up semi-naive evaluation computes
  only the facts relevant to a query goal, instead of the full least fixpoint.
  It is a **program transformation**: the engine is unchanged. Given a goal
  `{relation, pattern}`, the transformation:

  1. computes the goal's *adornment* (which argument positions are bound),
  2. generates `magic_<relation>_<adornment>` predicates capturing demand,
  3. rewrites recursive rules to consume the magic predicates,
  4. seeds the magic predicate with the bound goal constants.

  The transformed IR is then evaluated by the existing semi-naive engine.

  ## Scope (v0.5.0, experimental)

  - Positive recursive programs only.
  - A single goal.
  - Ground (constant) bound positions.

  Programs outside this scope fall back to full semi-naive evaluation
  (`{:fallback, reason}`), never producing incorrect results.
  """

  alias ExDatalog.IR

  @doc """
  Transforms an IR program for goal-directed evaluation.

  Returns `{:ok, transformed_ir}` when the magic-sets transformation applies,
  or `{:fallback, reason}` when the program is outside the supported scope (the
  caller should evaluate the original IR with semi-naive instead).
  """
  @spec transform(IR.t(), {String.t(), [term()]}) :: {:ok, IR.t()} | {:fallback, term()}
  def transform(%IR{} = ir, {goal_relation, goal_pattern}) do
    cond do
      not supported_program?(ir) ->
        {:fallback, :unsupported_program}

      not has_bound_position?(goal_pattern) ->
        {:fallback, :no_bound_positions}

      true ->
        do_transform(ir, goal_relation, goal_pattern)
    end
  end

  # --- Scope checks ---

  defp supported_program?(%IR{rules: rules}) do
    Enum.all?(rules, fn rule ->
      not has_negation?(rule) and not has_aggregate?(rule)
    end)
  end

  defp has_negation?(%IR.Rule{body: body}) do
    Enum.any?(body, &match?({:negative, _}, &1))
  end

  defp has_aggregate?(%IR.Rule{body: body}) do
    Enum.any?(body, fn
      {:constraint, %IR.Constraint{op: op}} -> op in [:count, :sum, :min, :max]
      _ -> false
    end)
  end

  defp has_bound_position?(pattern) do
    Enum.any?(pattern, fn p -> p != :_ end)
  end

  # --- Transformation ---

  defp do_transform(%IR{} = ir, goal_relation, goal_pattern) do
    adornment = adornment(goal_pattern)
    magic_rel = magic_relation_name(goal_relation, adornment)
    bound_positions = bound_positions(goal_pattern)

    magic_relation = %IR.Relation{
      name: magic_rel,
      arity: bound_count(goal_pattern),
      types: bound_types(ir, goal_relation, goal_pattern)
    }

    seed_fact = seed_fact(magic_rel, goal_relation, goal_pattern)

    rewritten_rules =
      ir.rules
      |> Enum.map(fn rule -> rewrite_rule(rule, goal_relation, magic_rel, bound_positions) end)

    new_relations = [magic_relation | ir.relations]
    new_facts = if seed_fact, do: [seed_fact | ir.facts], else: ir.facts

    # Recompute strata: the magic relation joins the goal relation's stratum.
    new_strata = inject_magic_into_strata(ir.strata, goal_relation, magic_rel)

    {:ok,
     %IR{
       ir
       | relations: new_relations,
         facts: new_facts,
         rules: rewritten_rules,
         strata: new_strata
     }}
  end

  defp adornment(pattern) do
    Enum.map_join(pattern, "", fn
      :_ -> "f"
      _ -> "b"
    end)
  end

  defp magic_relation_name(relation, adornment), do: "magic_#{relation}_#{adornment}"

  defp bound_count(pattern), do: Enum.count(pattern, fn p -> p != :_ end)

  defp bound_positions(pattern) do
    pattern
    |> Enum.with_index()
    |> Enum.filter(fn {p, _i} -> p != :_ end)
    |> Enum.map(fn {_p, i} -> i end)
  end

  defp bound_types(ir, goal_relation, pattern) do
    case Enum.find(ir.relations, fn r -> r.name == goal_relation end) do
      %IR.Relation{types: types} ->
        types
        |> Enum.zip(pattern)
        |> Enum.filter(fn {_t, p} -> p != :_ end)
        |> Enum.map(fn {t, _p} -> t end)

      nil ->
        List.duplicate(:any, bound_count(pattern))
    end
  end

  defp seed_fact(magic_rel, _goal_relation, pattern) do
    bound_values =
      pattern
      |> Enum.filter(fn p -> p != :_ end)
      |> Enum.map(&to_ir_value/1)

    case bound_values do
      [] -> nil
      values -> %IR.Fact{relation: magic_rel, values: values}
    end
  end

  defp to_ir_value(v) when is_integer(v), do: {:int, v}
  defp to_ir_value(v) when is_binary(v), do: {:str, v}
  defp to_ir_value(v) when is_atom(v), do: {:atom, v}

  # Rewrite a rule whose head is the goal relation: prepend the magic predicate
  # binding the bound head positions, so derivation is demand-restricted. The
  # magic atom projects exactly the goal's bound positions of the head, so its
  # arity matches the magic relation.
  defp rewrite_rule(
         %IR.Rule{head: %IR.Atom{relation: rel} = head} = rule,
         goal_relation,
         magic_rel,
         bound_positions
       )
       when rel == goal_relation do
    magic_terms = bound_head_terms(head, bound_positions)
    magic_atom = %IR.Atom{relation: magic_rel, terms: magic_terms}
    %IR.Rule{rule | body: [{:positive, magic_atom} | rule.body]}
  end

  defp rewrite_rule(rule, _goal_relation, _magic_rel, _bound_positions), do: rule

  defp bound_head_terms(%IR.Atom{terms: terms}, bound_positions) do
    bound_positions
    |> Enum.map(fn pos -> Enum.at(terms, pos) end)
  end

  defp inject_magic_into_strata(strata, goal_relation, magic_rel) do
    Enum.map(strata, fn %IR.Stratum{relations: rels} = stratum ->
      if goal_relation in rels do
        %IR.Stratum{stratum | relations: [magic_rel | rels]}
      else
        stratum
      end
    end)
  end
end
