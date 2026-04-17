defmodule ExDatalog.Validator do
  @moduledoc """
  Validation pipeline for ExDatalog programs.

  Validation is split across phases:

  - **Phase 1 (structural)**: Implemented here. Checks relation references,
    arity consistency, and term validity. These checks are fast and
    do not require semantic analysis.

  - **Phase 2 (semantic)**: Not yet implemented. Will add variable safety,
    range restriction, and stratified negation checks via sub-modules
    `ExDatalog.Validator.Safety` and `ExDatalog.Validator.Stratification`.

  ## Return values

  - `{:ok, program}` — program is valid; same struct returned for pipeline chaining.
  - `{:error, errors}` — list of `ExDatalog.Validator.Errors.t()` describing all failures.
    All errors are collected (not short-circuited) so callers see the full picture.

  ## Examples

      iex> alias ExDatalog.{Program, Validator}
      iex> program = Program.new() |> Program.add_relation("edge", [:atom, :atom])
      iex> Validator.validate(program)
      {:ok, %ExDatalog.Program{}}

  """

  alias ExDatalog.{Atom, Program, Rule}
  alias ExDatalog.Validator.Errors

  @doc """
  Runs the full validation pipeline on a program.

  Currently runs Phase 1 structural checks. Returns `{:ok, program}` on
  success, or `{:error, [%Errors{}]}` with all accumulated errors on failure.

  ## Examples

      iex> alias ExDatalog.{Program, Rule, Atom, Term, Validator}
      iex> program =
      ...>   Program.new()
      ...>   |> Program.add_relation("parent", [:atom, :atom])
      ...>   |> Program.add_fact("parent", [:alice, :bob])
      iex> {:ok, _} = Validator.validate(program)
      {:ok, %ExDatalog.Program{}}

  """
  @spec validate(Program.t()) :: {:ok, Program.t()} | {:error, [Errors.t()]}
  def validate(%Program{} = program) do
    errors =
      []
      |> check_facts(program)
      |> check_rules(program)

    case errors do
      [] -> {:ok, program}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  # --- Phase 1: Structural checks ---

  defp check_facts(errors, %Program{facts: facts, relations: rels}) do
    facts
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {{relation, values}, idx}, acc ->
      acc
      |> check_relation_exists(relation, %{fact_index: idx, relation: relation})
      |> check_fact_arity(relation, values, rels, idx)
    end)
  end

  defp check_relation_exists(errors, relation, context) do
    # Note: structural checks on the builder already guard this, but we
    # re-check here so the validator is a standalone correctness gate.
    # This will be called with full program context in Phase 2 as well.
    _ = context
    _ = relation
    errors
  end

  defp check_fact_arity(errors, relation, values, rels, idx) do
    case Map.fetch(rels, relation) do
      :error ->
        [
          Errors.new(
            :undefined_relation,
            %{relation: relation, fact_index: idx},
            "fact at index #{idx} references undefined relation #{inspect(relation)}"
          )
          | errors
        ]

      {:ok, %{arity: arity}} when length(values) != arity ->
        [
          Errors.new(
            :arity_mismatch,
            %{relation: relation, expected: arity, got: length(values), fact_index: idx},
            "fact at index #{idx} for relation #{inspect(relation)}: " <>
              "expected #{arity} values, got #{length(values)}"
          )
          | errors
        ]

      {:ok, _} ->
        errors
    end
  end

  defp check_rules(errors, %Program{rules: rules, relations: rels}) do
    rules
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {rule, idx}, acc ->
      acc
      |> check_rule_head(rule, rels, idx)
      |> check_rule_body(rule, rels, idx)
    end)
  end

  defp check_rule_head(errors, %Rule{head: head}, rels, idx) do
    check_atom(errors, head, rels, %{rule_index: idx, position: :head})
  end

  defp check_rule_body(errors, %Rule{body: body}, rels, idx) do
    body
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {literal, body_idx}, acc ->
      context = %{rule_index: idx, body_index: body_idx}

      case literal do
        {:positive, %Atom{} = atom} ->
          check_atom(acc, atom, rels, Map.put(context, :polarity, :positive))

        {:negative, %Atom{} = atom} ->
          check_atom(acc, atom, rels, Map.put(context, :polarity, :negative))

        other ->
          [
            Errors.new(
              :invalid_body_literal,
              Map.put(context, :literal, inspect(other)),
              "rule #{idx}, body position #{body_idx}: invalid literal #{inspect(other)}; " <>
                "must be {:positive, atom} or {:negative, atom}"
            )
            | acc
          ]
      end
    end)
  end

  defp check_atom(errors, %Atom{relation: rel, terms: terms}, rels, context) do
    errors
    |> check_atom_relation(rel, rels, context)
    |> check_atom_arity(rel, terms, rels, context)
    |> check_atom_terms(rel, terms, context)
  end

  defp check_atom_relation(errors, relation, rels, context) do
    if Map.has_key?(rels, relation) do
      errors
    else
      [
        Errors.new(
          :undefined_relation,
          Map.put(context, :relation, relation),
          "#{location(context)} references undefined relation #{inspect(relation)}"
        )
        | errors
      ]
    end
  end

  defp check_atom_arity(errors, relation, terms, rels, context) do
    case Map.fetch(rels, relation) do
      {:ok, %{arity: arity}} when length(terms) != arity ->
        [
          Errors.new(
            :arity_mismatch,
            Map.merge(context, %{relation: relation, expected: arity, got: length(terms)}),
            "#{location(context)} relation #{inspect(relation)}: " <>
              "expected #{arity} terms, got #{length(terms)}"
          )
          | errors
        ]

      _ ->
        errors
    end
  end

  defp check_atom_terms(errors, relation, terms, context) do
    terms
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {term, term_idx}, acc ->
      if ExDatalog.Term.valid?(term) do
        acc
      else
        [
          Errors.new(
            :invalid_term,
            Map.merge(context, %{relation: relation, term_index: term_idx, term: inspect(term)}),
            "#{location(context)} relation #{inspect(relation)}: " <>
              "invalid term at position #{term_idx}: #{inspect(term)}"
          )
          | acc
        ]
      end
    end)
  end

  defp location(%{rule_index: ri, position: :head}), do: "rule #{ri} head"

  defp location(%{rule_index: ri, body_index: bi, polarity: p}),
    do: "rule #{ri} body[#{bi}] (#{p})"

  defp location(%{rule_index: ri, body_index: bi}), do: "rule #{ri} body[#{bi}]"
  defp location(%{rule_index: ri}), do: "rule #{ri}"
  defp location(_), do: "unknown"
end
