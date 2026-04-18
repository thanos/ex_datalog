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
  @spec eval_rule_iteration(IR.Rule.t(), relation_facts(), relation_facts(), relation_facts()) ::
          [tuple()]
  def eval_rule_iteration(rule, full, delta, old) do
    positive_body = positive_atoms(rule)
    k = length(positive_body)

    head_relation = rule.head.relation
    existing = Map.get(full, head_relation, MapSet.new())

    if k == 0 do
      derived = eval_fact_rule(rule, full)
      derived |> MapSet.new() |> MapSet.difference(existing) |> MapSet.to_list()
    else
      0..(k - 1)
      |> Enum.flat_map(&eval_variant_if_delta(rule, positive_body, full, delta, old, &1))
      |> MapSet.new()
      |> MapSet.difference(existing)
      |> MapSet.to_list()
    end
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

  defp eval_fact_rule(rule, full) do
    bindings = [%{}]

    bindings =
      Enum.reduce(rule.body, bindings, fn
        {:positive, atom}, acc ->
          tuples = MapSet.to_list(Map.get(full, atom.relation, MapSet.new()))
          Join.join(acc, atom.terms, tuples)

        {:negative, atom}, acc ->
          Enum.filter(acc, fn b -> check_negative_atom(atom, b, full) end)

        {:constraint, c}, acc ->
          apply_constraint_to_bindings(c, acc)
      end)

    case bindings do
      [] -> []
      _ -> Enum.map(bindings, &Join.project(rule.head, &1))
    end
  end

  defp apply_constraint_to_bindings(constraint, bindings) do
    Enum.flat_map(bindings, fn b ->
      case ConstraintEval.apply_one(constraint, b) do
        {:ok, new_b} -> [new_b]
        :filter -> []
      end
    end)
  end

  defp eval_variant(rule, positive_body, full, delta, old, delta_pos) do
    bindings = [%{}]

    bindings =
      positive_body
      |> Enum.with_index()
      |> Enum.reduce(bindings, fn {atom, idx}, acc ->
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

    bindings = apply_constraints(rule.body, bindings)
    bindings = apply_negation(rule.body, bindings, full)

    case bindings do
      [] -> []
      _ -> Enum.map(bindings, &Join.project(rule.head, &1))
    end
  end

  defp eval_variant_if_delta(rule, positive_body, full, delta, old, delta_pos) do
    delta_relation = Enum.at(positive_body, delta_pos).relation

    if MapSet.size(Map.get(delta, delta_relation, MapSet.new())) == 0 do
      []
    else
      eval_variant(rule, positive_body, full, delta, old, delta_pos)
    end
  end

  defp apply_constraints(body, bindings) do
    constraints = for {:constraint, c} <- body, do: c

    Enum.flat_map(bindings, fn b ->
      case ConstraintEval.apply(constraints, b) do
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
