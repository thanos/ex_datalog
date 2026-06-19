defmodule ExDatalog.Knowledge do
  @moduledoc """
  The complete knowledge base produced by Datalog evaluation.

  Contains the derived fact sets for every relation, along with evaluation
  statistics (iteration count, duration, relation sizes).

  The name reflects what this struct *is*: after applying all rules to all
  facts until no new facts can be derived, you have a **knowledge base** —
  every relation fully materialised, every derivable fact present. You then
  *query* this knowledge with `get/2` and `match/3`.

  When provenance tracking is enabled (via `explain: true`), the `provenance`
  field records which rule derived each fact. Base facts (EDB) are attributed
  as `:base`. This field is `nil` when provenance tracking is disabled,
  ensuring zero overhead for the common case.

  ## Access functions

  - `get/2` — all tuples for a relation.
  - `match/3` — tuples matching a pattern (`:_` for wildcard).
  - `size/2` — number of tuples in a relation.
  - `relations/1` — list of all relation names in the knowledge base.
  """

  @type provenance :: %{
          fact_origins: %{String.t() => %{tuple() => non_neg_integer() | :base}},
          rules: %{non_neg_integer() => ExDatalog.IR.Rule.t()}
        }

  @type stats :: %{
          iterations: non_neg_integer(),
          duration_us: non_neg_integer(),
          relation_sizes: %{String.t() => non_neg_integer()},
          capabilities: ExDatalog.Capabilities.t()
        }

  @type t :: %__MODULE__{
          relations: %{String.t() => MapSet.t(tuple())},
          stats: stats(),
          provenance: provenance() | nil
        }

  defstruct [:relations, :stats, provenance: nil]

  @doc """
  Returns all tuples for a relation as a MapSet.

  ## Examples

      iex> knowledge = %ExDatalog.Knowledge{relations: %{"parent" => MapSet.new([{:alice, :bob}])}, stats: %{iterations: 1, duration_us: 0, relation_sizes: %{"parent" => 1}}}
      iex> ExDatalog.Knowledge.get(knowledge, "parent") |> MapSet.to_list()
      [{:alice, :bob}]

  """
  @spec get(t(), String.t()) :: MapSet.t(tuple())
  def get(%__MODULE__{relations: rels}, relation) do
    Map.get(rels, relation, MapSet.new())
  end

  @doc """
  Returns tuples matching a pattern.

  The pattern is a list where `:_` matches any value and other values match
  exactly. Useful for querying specific facts.

  ## Examples

      iex> knowledge = %ExDatalog.Knowledge{relations: %{"parent" => MapSet.new([{:alice, :bob}, {:carol, :dave}, {:alice, :carol}])}, stats: %{iterations: 1, duration_us: 0, relation_sizes: %{"parent" => 3}}}
      iex> ExDatalog.Knowledge.match(knowledge, "parent", [:alice, :_]) |> MapSet.to_list() |> Enum.sort()
      [{:alice, :bob}, {:alice, :carol}]

  """
  @spec match(t(), String.t(), [term()]) :: MapSet.t(tuple())
  def match(%__MODULE__{relations: rels}, relation, pattern) do
    tuples = Map.get(rels, relation, MapSet.new())

    Enum.reduce(tuples, MapSet.new(), fn tuple, acc ->
      if matches_pattern?(tuple, pattern) do
        MapSet.put(acc, tuple)
      else
        acc
      end
    end)
  end

  @doc """
  Returns the number of tuples in a relation.

  ## Examples

      iex> knowledge = %ExDatalog.Knowledge{relations: %{"parent" => MapSet.new([{:alice, :bob}, {:carol, :dave}])}, stats: %{iterations: 1, duration_us: 0, relation_sizes: %{"parent" => 2}}}
      iex> ExDatalog.Knowledge.size(knowledge, "parent")
      2

  """
  @spec size(t(), String.t()) :: non_neg_integer()
  def size(%__MODULE__{relations: rels}, relation) do
    rels |> Map.get(relation, MapSet.new()) |> MapSet.size()
  end

  @doc """
  Returns all relation names present in the knowledge base.

  ## Examples

      iex> knowledge = %ExDatalog.Knowledge{relations: %{"parent" => MapSet.new(), "ancestor" => MapSet.new()}, stats: %{iterations: 1, duration_us: 0, relation_sizes: %{}}}
      iex> Enum.sort(ExDatalog.Knowledge.relations(knowledge))
      ["ancestor", "parent"]

  """
  @spec relations(t()) :: [String.t()]
  def relations(%__MODULE__{relations: rels}), do: Map.keys(rels) |> Enum.sort()

  defp matches_pattern?(tuple, pattern) do
    size = tuple_size(tuple)
    length = length(pattern)

    if size != length do
      false
    else
      pattern
      |> Enum.with_index()
      |> Enum.all?(fn
        {:_, _idx} -> true
        {val, idx} -> elem(tuple, idx) == val
      end)
    end
  end
end
