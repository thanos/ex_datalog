defmodule ExDatalog.Explain do
  @moduledoc """
  Derivation tree explanation for Datalog query results.

  When a query is executed with `explain: true`, the result includes provenance
  data recording which rule derived each fact. This module reconstructs the
  derivation tree from that provenance data.

  A derivation tree node is either `:base_fact` (for EDB facts) or a
  `%Node{}` struct containing the fact, the rule that derived it, and
  child nodes for each body atom that contributed.

  ## Usage

      {:ok, result} = ExDatalog.query(program, explain: true)
      {:ok, tree} = ExDatalog.Explain.explain(result, "ancestor", {:alice, :carol})

  The tree shows how the fact was derived, recursively expanding each derived
  body atom back to its own derivation. EDB facts terminate as `:base_fact`.
  """

  alias ExDatalog.{IR, Result}

  defmodule Node do
    @moduledoc """
    A node in a derivation tree representing a rule-derived fact.

    ## Fields

    - `fact` — the derived tuple.
    - `rule_id` — which rule produced this fact (references the IR rule).
    - `children` — derivation nodes for the body atoms that contributed.
      Only positive body atoms have children; negative atoms and constraints
      do not.
    """

    @enforce_keys [:fact, :rule_id, :children]
    defstruct [:fact, :rule_id, :children]

    @type t :: %__MODULE__{
            fact: tuple(),
            rule_id: non_neg_integer(),
            children: [ExDatalog.Explain.derivation()]
          }
  end

  @type derivation :: :base_fact | Node.t()

  @doc """
  Returns the derivation tree for a specific fact in the result.

  Requires the result to have been produced with `explain: true`.
  Returns `{:error, :no_provenance}` if provenance tracking was not enabled,
  `{:error, :not_found}` if the fact is not in the result, or `{:ok, tree}`
  with the derivation tree.

  ## Examples

      iex> alias ExDatalog.{Program, Rule, Atom, Term, Explain}
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
      iex> {:ok, result} = ExDatalog.query(program, explain: true)
      iex> {:ok, tree} = Explain.explain(result, "ancestor", {:alice, :bob})
      iex> tree.rule_id
      0
  """
  @spec explain(Result.t(), String.t(), tuple()) ::
          {:ok, derivation()} | {:error, :no_provenance | :not_found}
  def explain(%Result{provenance: nil}, _relation, _tuple) do
    {:error, :no_provenance}
  end

  def explain(%Result{provenance: provenance}, relation, tuple) do
    %{fact_origins: origins} = provenance
    build_tree(relation, tuple, origins, provenance.rules, %{})
  end

  defp build_tree(relation, tuple, origins, rules, visited) do
    key = {relation, tuple}

    if Map.has_key?(visited, key) do
      cycle_node(relation, tuple, origins)
    else
      build_derivation(relation, tuple, origins, rules, key, visited)
    end
  end

  defp build_derivation(relation, tuple, origins, rules, key, visited) do
    relation_origins = Map.get(origins, relation, %{})

    case Map.get(relation_origins, tuple) do
      nil ->
        {:error, :not_found}

      :base ->
        {:ok, :base_fact}

      rule_id ->
        expand_rule_derivation(tuple, rule_id, origins, rules, key, visited)
    end
  end

  defp expand_rule_derivation(tuple, rule_id, origins, rules, key, visited) do
    rule = Map.fetch!(rules, rule_id)
    visited = Map.put(visited, key, true)

    children =
      rule.body
      |> Enum.flat_map(&body_atom_children(&1, origins, rules, visited))

    {:ok, %Node{fact: tuple, rule_id: rule_id, children: children}}
  end

  defp body_atom_children({:positive, %IR.Atom{relation: body_rel}}, origins, rules, visited) do
    expand_body_relation(body_rel, origins, rules, visited)
  end

  defp body_atom_children({:negative, _}, _origins, _rules, _visited), do: []
  defp body_atom_children({:constraint, _}, _origins, _rules, _visited), do: []

  defp cycle_node(relation, tuple, origins) do
    rule_id = Map.get(Map.get(origins, relation, %{}), tuple)
    {:ok, %Node{fact: tuple, rule_id: rule_id, children: []}}
  end

  defp expand_body_relation(body_rel, origins, rules, visited) do
    body_origins = Map.get(origins, body_rel, %{})

    Enum.map(body_origins, fn {tuple, origin} ->
      expand_origin(tuple, origin, body_rel, origins, rules, visited)
    end)
  end

  defp expand_origin(_tuple, :base, _body_rel, _origins, _rules, _visited) do
    :base_fact
  end

  defp expand_origin(tuple, rule_id, body_rel, origins, rules, visited) do
    case build_tree(body_rel, tuple, origins, rules, visited) do
      {:ok, tree} -> tree
      {:error, _} -> %Node{fact: tuple, rule_id: rule_id, children: []}
    end
  end
end
