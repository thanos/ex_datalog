defmodule ExDatalog.Engine.Evaluator do
  @moduledoc """
  Single-rule evaluation using k-position semi-naive delta computation.

  For a rule with k body atoms, each fixpoint iteration evaluates k variants.
  Variant i places the delta at body position i, uses full (existing + delta)
  for positions before i, and uses old (pre-iteration snapshot) for positions
  after i. This guarantees every derivation that involves at least one delta
  fact is counted exactly once, avoiding duplicates.

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

  Returns a `MapSet` of head tuples derived by this rule in this iteration.
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
      eval_fact_rule(rule, full)
    else
      derived =
        0..(k - 1)
        |> Enum.flat_map(fn delta_pos ->
          eval_variant(rule, positive_body, full, delta, old, delta_pos)
        end)
        |> MapSet.new()
        |> MapSet.difference(existing)
        |> MapSet.to_list()

      derived
    end
  end

  defp positive_atoms(%IR.Rule{body: body}) do
    body
    |> Enum.filter(fn
      {:positive, %IR.Atom{}} -> true
      _ -> false
    end)
    |> Enum.map(fn {:positive, atom} -> atom end)
  end

  defp eval_fact_rule(rule, full) do
    bindings = [%{}]

    bindings =
      Enum.reduce(rule.body, bindings, fn
        {:positive, atom}, acc ->
          tuples = MapSet.to_list(Map.get(full, atom.relation, MapSet.new()))
          Join.join(acc, atom.terms, tuples)

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

    case bindings do
      [] -> []
      _ -> Enum.map(bindings, &Join.project(rule.head, &1))
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
end
