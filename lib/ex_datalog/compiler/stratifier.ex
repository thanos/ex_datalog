defmodule ExDatalog.Compiler.Stratifier do
  @moduledoc """
  Assigns strata to relations and rules in a validated Datalog program.

  Uses `ExDatalog.Validator.Stratification` for SCC computation and
  stratum assignment. This module bridges the validator and the IR compiler,
  producing a deterministic stratum assignment that the engine uses to
  evaluate strata in order.
  """

  alias ExDatalog.Program
  alias ExDatalog.Validator.Stratification

  @doc """
  Assigns a stratum to each rule in the program.

  Returns a map from rule index (0-based, in canonical order) to its
  stratum number. Rules are ordered by their position in the program's
  rules list after validation.
  """
  @spec assign(Program.t()) :: %{non_neg_integer() => non_neg_integer()}
  def assign(%Program{} = program) do
    strata = Stratification.assign_strata(program)

    program.rules
    |> Enum.with_index()
    |> Enum.map(fn {rule, idx} ->
      head_rel = rule.head.relation
      stratum = Map.get(strata, head_rel, 0)
      {idx, stratum}
    end)
    |> Map.new()
  end

  @doc """
  Computes stratum structures for the IR.

  Returns a list of `ExDatalog.IR.Stratum` structs, one per distinct stratum,
  ordered by stratum index. Each stratum contains the rule IDs and relation
  names that belong to it.

  EDB-only relations (no rules defining them) are always in stratum 0.
  """
  @spec compute_strata(Program.t()) :: [ExDatalog.IR.Stratum.t()]
  def compute_strata(%Program{} = program) do
    strata = Stratification.assign_strata(program)
    rule_strata = assign(program)

    max_stratum =
      case Map.values(strata) do
        [] -> 0
        vals -> Enum.max(vals)
      end

    indexed_rules =
      program.rules
      |> Enum.with_index()
      |> Enum.map(fn {rule, idx} ->
        {Map.get(rule_strata, idx, 0), idx, rule.head.relation}
      end)

    grouped = Enum.group_by(indexed_rules, fn {stratum, _idx, _rel} -> stratum end)

    for stratum_idx <- 0..max_stratum do
      rules_in_stratum = Map.get(grouped, stratum_idx, [])
      rule_ids = Enum.map(rules_in_stratum, fn {_s, id, _r} -> id end)
      relations = rules_in_stratum |> Enum.map(fn {_s, _id, rel} -> rel end) |> Enum.uniq()

      %ExDatalog.IR.Stratum{
        index: stratum_idx,
        rule_ids: rule_ids,
        relations: relations
      }
    end
  end
end
