defmodule ExDatalog.Validator do
  @moduledoc """
  Validation pipeline for ExDatalog programs.

  Validates a program in two stages:

  - **Phase 1 (structural)**: Checks relation references, arity consistency,
    and term validity. Runs on every `validate/1` call.

  - **Phase 2 (semantic)**: Checks variable safety, range restriction,
    wildcard-in-head, constraint binding, and stratified negation. Runs on
    every `validate/1` call after Phase 1 succeeds.

  All errors are collected (not short-circuited) so callers see the full
  picture. Returns `{:ok, program}` on success or `{:error, [errors]}` on
  failure.

  ## Examples

      iex> alias ExDatalog.{Program, Validator}
      iex> program = Program.new() |> Program.add_relation("edge", [:atom, :atom])
      iex> Validator.validate(program)
      {:ok, %ExDatalog.Program{}}

  """

  alias ExDatalog.{Atom, Program, Rule}
  alias ExDatalog.Validator.{Error, Safety, Stratification}

  @doc """
  Runs the full validation pipeline (structural + semantic) on a program.

  Returns `{:ok, program}` on success, or `{:error, [%Error{}]}` with all
  accumulated errors on failure.
  """
  @spec validate(Program.t()) :: {:ok, Program.t()} | {:error, [Error.t()]}
  def validate(%Program{} = program) do
    # Normalize insertion order: the builder prepends facts and rules for O(1)
    # per-call cost; we reverse once here so validation and the returned program
    # both see facts/rules in the order they were added.
    program = %{program | facts: Enum.reverse(program.facts), rules: Enum.reverse(program.rules)}

    errors =
      []
      |> check_facts(program)
      |> check_rules(program)
      |> check_safety(program)
      |> check_stratification(program)

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
      |> check_fact_undefined_relation(relation, rels, idx)
      |> check_fact_arity(relation, values, rels, idx)
    end)
  end

  defp check_fact_undefined_relation(errors, relation, rels, idx) do
    if Map.has_key?(rels, relation) do
      errors
    else
      [
        Error.new(
          :undefined_relation,
          %{relation: relation, fact_index: idx},
          "fact at index #{idx} references undefined relation #{inspect(relation)}"
        )
        | errors
      ]
    end
  end

  defp check_fact_arity(errors, relation, values, rels, idx) do
    case Map.fetch(rels, relation) do
      {:ok, %{arity: arity}} when length(values) != arity ->
        [
          Error.new(
            :arity_mismatch,
            %{relation: relation, expected: arity, got: length(values), fact_index: idx},
            "fact at index #{idx} for relation #{inspect(relation)}: " <>
              "expected #{arity} values, got #{length(values)}"
          )
          | errors
        ]

      _ ->
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
            Error.new(
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
        Error.new(
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
          Error.new(
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
          Error.new(
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

  # --- Phase 2: Semantic checks ---

  defp check_safety(errors, %Program{rules: []}) do
    errors
  end

  defp check_safety(errors, %Program{} = program) do
    Enum.reduce(Safety.check(program), errors, &[&1 | &2])
  end

  defp check_stratification(errors, %Program{rules: []}) do
    errors
  end

  defp check_stratification(errors, %Program{} = program) do
    case Stratification.check(program) do
      :ok -> errors
      {:error, strat_errors} -> Enum.reduce(strat_errors, errors, &[&1 | &2])
    end
  end

  # --- Helpers ---

  defp location(%{rule_index: ri, position: :head}), do: "rule #{ri} head"

  defp location(%{rule_index: ri, body_index: bi, polarity: p}),
    do: "rule #{ri} body[#{bi}] (#{p})"

  defp location(%{rule_index: ri, body_index: bi}), do: "rule #{ri} body[#{bi}]"
  defp location(%{rule_index: ri}), do: "rule #{ri}"
end
