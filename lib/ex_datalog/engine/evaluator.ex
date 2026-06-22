defmodule ExDatalog.Engine.Evaluator do
  @moduledoc """
  Single-rule evaluation using k-position semi-naive delta computation.

  For a rule with k positive body atoms, each fixpoint iteration evaluates k
  variants. Variant i places the delta at body position i, uses full
  (existing + delta) for positions before i, and uses old (pre-iteration
  snapshot) for positions after i. This guarantees every derivation that
  involves at least one delta fact is counted exactly once, avoiding duplicates.

  ## Negation handling

  Negative body atoms (`{:negative, %IR.Atom{}}`) are **filters**, not
  participants in the k-position delta scheme. After all positive atoms are
  joined and constraints applied, each binding is checked against the negative
  atoms: a binding survives only if no tuple in the `full` relation matches
  the negative atom's terms under that binding. This ensures negation is
  evaluated against the fully-materialised lower-stratum relation, which is
  correct for stratified Datalog.

  ## Four views per relation

  The evaluator receives four logical "views" of each relation per iteration:

  - `full` — all facts currently known (existing + delta from previous iter).
  - `old` — snapshot of the relation at the start of the current iteration.
  - `delta` — facts newly derived in the previous iteration.

  For the initial iteration (i=0), `delta` is the EDB (base facts) and `old`
  is empty.

  ## Constraint handling

  After all body atoms are joined, constraints are applied sequentially.
  Comparisons filter bindings; arithmetic constraints extend bindings with
  their result variable. This matches the validator's sequential constraint
  ordering guarantee.
  """

  alias ExDatalog.Constraints.{Aggregate, BeamCallback}
  alias ExDatalog.Engine.{Binding, ConstraintEval, Join}
  alias ExDatalog.IR

  @type binding :: Binding.t()
  @type relation_facts :: %{String.t() => MapSet.t(tuple())}

  @doc """
  Evaluates a single rule for one fixpoint iteration using k-position delta.

  Returns a list of head tuples derived by this rule in this iteration.
  Each tuple is an Elixir tuple of native values.

  Parameters:

  - `rule` — the IR rule to evaluate.
  - `full` — map from relation name to the full fact set.
  - `delta` — map from relation name to delta facts (newly derived).
  - `old` — map from relation name to old facts (pre-iteration snapshot).

  For variant i (0 ≤ i < k, where k is the number of positive body atoms):

  - Position i uses `delta(relation_i)`
  - Positions j < i use `full(relation_j)`
  - Positions j > i use `old(relation_j)`

  Negative atoms are applied as filters after the join, checking that no tuple
  in the `full` relation matches under the current binding.

  The results of all variants are unioned, then deduplicated against `full`
  for the head relation.
  """
  @spec eval_rule_iteration(
          IR.Rule.t(),
          relation_facts(),
          relation_facts(),
          relation_facts(),
          ExDatalog.Constraint.Context.t()
        ) ::
          [tuple()]
  def eval_rule_iteration(rule, full, delta, old, ctx \\ %ExDatalog.Constraint.Context{}) do
    head_relation = rule.head.relation
    existing = Map.get(full, head_relation, MapSet.new())

    if aggregate_rule?(rule) do
      rule
      |> eval_aggregate_rule(full, ctx)
      |> MapSet.new()
      |> MapSet.difference(existing)
      |> MapSet.to_list()
    else
      eval_normal_rule(rule, full, delta, old, ctx, existing)
    end
  end

  defp eval_normal_rule(rule, full, delta, old, ctx, existing) do
    positive_body = positive_atoms(rule)
    k = length(positive_body)

    if k == 0 do
      derived =
        [%{}]
        |> join_positive_body(rule.body, full)
        |> finish_bindings(rule, full, ctx)

      derived |> MapSet.new() |> MapSet.difference(existing) |> MapSet.to_list()
    else
      0..(k - 1)
      |> Enum.flat_map(&eval_variant_if_delta(rule, positive_body, full, delta, old, &1, ctx))
      |> MapSet.new()
      |> MapSet.difference(existing)
      |> MapSet.to_list()
    end
  end

  defp aggregate_rule?(%IR.Rule{body: body}) do
    Enum.any?(body, fn
      {:constraint, %ExDatalog.IR.Constraint{op: op}} -> op in [:count, :sum, :min, :max]
      _ -> false
    end)
  end

  # Aggregate rules are stratified above their source relations, so all source
  # facts are final in `full`. We join the positive body against `full`, apply
  # non-aggregate filters and negation, group by the head variables other than
  # the aggregate result, reduce each group, then project.
  defp eval_aggregate_rule(%IR.Rule{} = rule, full, ctx) do
    agg_constraint = find_aggregate(rule.body)

    joined = join_positive_body([%{}], rule.body, full)
    filtered = apply_constraints(rule.body, joined, ctx)
    with_callbacks = apply_callbacks(rule.body, filtered, ctx)
    bindings = apply_negation(rule.body, with_callbacks, full)

    %ExDatalog.IR.Constraint{op: op, left: {:var, input_var}, result: {:var, result_var}} =
      agg_constraint

    group_vars = aggregate_group_vars(rule.head, result_var)

    bindings
    |> Aggregate.group_and_reduce(group_vars, op, input_var, result_var)
    |> Enum.map(&Join.project(rule.head, &1))
  end

  defp find_aggregate(body) do
    Enum.find_value(body, fn
      {:constraint, %ExDatalog.IR.Constraint{op: op} = c} when op in [:count, :sum, :min, :max] ->
        c

      _ ->
        nil
    end)
  end

  # Group by the head variables other than the aggregate result variable.
  defp aggregate_group_vars(%IR.Atom{terms: terms}, result_var) do
    terms
    |> Enum.flat_map(fn
      {:var, name} -> [name]
      _ -> []
    end)
    |> Enum.reject(fn name -> name == result_var end)
    |> Enum.uniq()
  end

  @doc """
  Checks whether a binding satisfies a negative body atom.

  A negative atom `not R(t1, ..., tn)` is satisfied when no tuple in `full`
  for relation `R` matches the atom's terms under the given binding. If the
  atom's terms contain variables already bound, only tuples consistent with
  those bindings are considered. If the atom's terms contain only wildcards,
  any tuple in the relation causes the negative atom to fail.

  Returns `true` if the binding passes (no matching tuple), `false` otherwise.
  """
  @spec check_negative_atom(IR.Atom.t(), binding(), relation_facts()) :: boolean()
  def check_negative_atom(%IR.Atom{relation: relation, terms: terms}, binding, full) do
    tuples = Map.get(full, relation, MapSet.new())

    not Enum.any?(tuples, fn tuple ->
      case Join.match_tuple(terms, tuple, binding) do
        {:ok, _extended} -> true
        :no_match -> false
      end
    end)
  end

  defp positive_atoms(%IR.Rule{body: body}) do
    for {:positive, %IR.Atom{} = atom} <- body, do: atom
  end

  defp join_positive_body(initial_bindings, body, full) do
    positive_atoms = for {:positive, %IR.Atom{} = atom} <- body, do: atom

    Enum.reduce(positive_atoms, initial_bindings, fn atom, bindings ->
      tuples = MapSet.to_list(Map.get(full, atom.relation, MapSet.new()))
      Join.join(bindings, atom.terms, tuples)
    end)
  end

  defp finish_bindings(bindings, rule, full, ctx) do
    bindings = apply_constraints(rule.body, bindings, ctx)
    bindings = apply_callbacks(rule.body, bindings, ctx)
    bindings = apply_negation(rule.body, bindings, full)

    case bindings do
      [] -> []
      _ -> Enum.map(bindings, &Join.project(rule.head, &1))
    end
  end

  defp apply_callbacks(body, bindings, ctx) do
    callbacks = for {:callback, cb} <- body, do: cb

    case callbacks do
      [] ->
        bindings

      _ ->
        opts = callback_opts(ctx)

        Enum.flat_map(bindings, fn binding ->
          apply_callback_chain(callbacks, binding, opts)
        end)
    end
  end

  defp apply_callback_chain(callbacks, binding, opts) do
    Enum.reduce_while(callbacks, [binding], fn cb, [b] ->
      step_callback(BeamCallback.apply_callback(cb, b, opts))
    end)
  end

  defp step_callback({:ok, new_b}), do: {:cont, [new_b]}
  defp step_callback(:filter), do: {:halt, []}

  defp callback_opts(%ExDatalog.Constraint.Context{opts: opts}) when is_list(opts), do: opts
  defp callback_opts(_), do: []

  defp eval_variant(rule, positive_body, full, delta, old, delta_pos, ctx) do
    bindings =
      positive_body
      |> Enum.with_index()
      |> Enum.reduce([%{}], fn {atom, idx}, acc ->
        relation = atom.relation

        tuples =
          cond do
            idx == delta_pos ->
              MapSet.to_list(Map.get(delta, relation, MapSet.new()))

            idx < delta_pos ->
              MapSet.to_list(Map.get(full, relation, MapSet.new()))

            true ->
              MapSet.to_list(Map.get(old, relation, MapSet.new()))
          end

        Join.join(acc, atom.terms, tuples)
      end)

    finish_bindings(bindings, rule, full, ctx)
  end

  defp eval_variant_if_delta(rule, positive_body, full, delta, old, delta_pos, ctx) do
    delta_relation = Enum.at(positive_body, delta_pos).relation

    if MapSet.size(Map.get(delta, delta_relation, MapSet.new())) == 0 do
      []
    else
      eval_variant(rule, positive_body, full, delta, old, delta_pos, ctx)
    end
  end

  defp apply_constraints(body, bindings, ctx) do
    # Aggregate constraints are NOT evaluated per binding; they are handled by
    # the group-and-reduce aggregate path. Exclude them here so the normal
    # per-binding pipeline never feeds them to ConstraintEval.
    constraints =
      for {:constraint, %ExDatalog.IR.Constraint{op: op} = c} <- body,
          op not in [:count, :sum, :min, :max],
          do: c

    Enum.flat_map(bindings, fn b ->
      case ConstraintEval.apply(constraints, b, ctx) do
        {:ok, new_b} -> [new_b]
        :filter -> []
      end
    end)
  end

  defp apply_negation(body, bindings, full) do
    negative_atoms = for {:negative, atom} <- body, do: atom

    Enum.filter(bindings, fn binding ->
      Enum.all?(negative_atoms, fn atom ->
        check_negative_atom(atom, binding, full)
      end)
    end)
  end
end
