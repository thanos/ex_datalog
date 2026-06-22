defmodule ExDatalog do
  @moduledoc """
  ExDatalog — a pure Elixir Datalog engine.

  ## Overview

  ExDatalog implements a bottom-up Datalog evaluation engine with
  semi-naive fixpoint computation. Programs are built using a
  builder API, validated, compiled to an intermediate representation,
  and evaluated by a pluggable engine backend.

  ## Quick Start

       alias ExDatalog
       alias ExDatalog.{Program, Rule, Atom, Term}

       {:ok, knowledge} =
         Program.new()
         |> Program.add_relation("parent", [:atom, :atom])
         |> Program.add_relation("ancestor", [:atom, :atom])
         |> Program.add_fact("parent", [:alice, :bob])
         |> Program.add_fact("parent", [:bob, :carol])
         |> Program.add_rule(
              Rule.new(
                Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
                [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
              )
            )
         |> Program.add_rule(
              Rule.new(
                Atom.new("ancestor", [Term.var("X"), Term.var("Z")]),
                [
                  {:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])},
                  {:positive, Atom.new("ancestor", [Term.var("Y"), Term.var("Z")])}
                ]
              )
            )
         |> ExDatalog.materialize()

  ## Pipeline

  The evaluation pipeline is:

  1. `ExDatalog.Program` — builder API
  2. `ExDatalog.Validator` — structural + semantic validation
  3. `ExDatalog.Compiler` — AST to IR
  4. `ExDatalog.Engine` — pluggable evaluation backend
  5. `ExDatalog.Knowledge` — the knowledge base produced by evaluation

  Each step can be invoked individually:

       {:ok, validated} = ExDatalog.validate(program)
       {:ok, ir}        = ExDatalog.compile(program)
       {:ok, knowledge}  = ExDatalog.evaluate(ir, [])

  ## Options

  `materialize/2` and `evaluate/2` accept:

   - `engine` — backend module (default: `ExDatalog.Engine.Naive`)
   - `storage` — storage module (default: `ExDatalog.Storage.Map`)
   - `max_iterations` — fixpoint iteration limit (default: 10_000)
   - `timeout_ms` — wall-clock timeout in milliseconds (default: 30_000)
   - `strategy` — `:semi_naive` (default) or `:magic_sets`
   - `goal` — `{relation_name, pattern}` used as the magic-sets goal
     (when `strategy: :magic_sets`) and as a post-materialization filter
     (default: `nil`). See `materialize/2` for details.
   - `explain` — enable provenance tracking (default: `false`)

  If `max_iterations` or `timeout_ms` is hit, the returned `Knowledge.t()`
  will have `stats.termination` set to `:iteration_limit` or `:timeout`
  respectively. A successful fixpoint has `stats.termination == :fixpoint`.
  Callers **must** check this field to distinguish complete from truncated
  results.
  """

  alias ExDatalog.{Program, Validator}

  @doc """
  Creates a new, empty Datalog program.

  Delegates to `ExDatalog.Program.new/0`.

  ## Examples

       iex> ExDatalog.new()
       %ExDatalog.Program{relations: %{}, facts: [], rules: []}

       iex> alias ExDatalog.Program
       iex> ExDatalog.new() |> Program.add_relation("edge", [:atom, :atom])
       %ExDatalog.Program{relations: %{"edge" => %{arity: 2, types: [:atom, :atom]}}, facts: [], rules: []}

  """
  @spec new() :: Program.t()
  defdelegate new(), to: Program

  @doc """
  Validates a program, returning structural and semantic errors.

  Returns `{:ok, program}` if valid, `{:error, errors}` otherwise.
  `errors` is a list of `ExDatalog.Validator.Error.t()`.

  Structural checks (Phase 1):
  - Relation references exist.
  - Arities match declared schemas.
  - Terms are valid.

  Semantic checks (Phase 2):
  - Variable safety and range restriction.
  - Constraint binding and ordering.
  - Stratified negation.

  ## Examples

       iex> alias ExDatalog.Program
       iex> program = Program.new() |> Program.add_relation("edge", [:atom, :atom])
       iex> {:ok, validated} = ExDatalog.validate(program)
       iex> is_struct(validated, ExDatalog.Program)
       true

  """
  @spec validate(Program.t()) :: {:ok, Program.t()} | {:error, [Validator.Error.t()]}
  def validate(%Program{} = program) do
    Validator.validate(program)
  end

  def validate({:error, _} = error), do: error

  @doc """
  Compiles a validated program to an engine-neutral IR.

  Runs validation first. Returns `{:ok, %ExDatalog.IR{}}` or
  `{:error, errors}`.

  The IR is deterministic: the same program always produces the same IR.
  Rules are sorted by `(stratum, relation_name, rule_id)`. Facts are sorted
  by `(relation_name, values)`. Relations are sorted by name.

  ## Examples

       iex> alias ExDatalog.{Program, Rule, Atom, Term}
       iex> program =
       ...>   Program.new()
       ...>   |> Program.add_relation("edge", [:atom, :atom])
       ...>   |> Program.add_relation("path", [:atom, :atom])
       ...>   |> Program.add_rule(
       ...>     Rule.new(
       ...>       Atom.new("path", [Term.var("X"), Term.var("Y")]),
       ...>       [{:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}]
       ...>     )
       ...>   )
       iex> {:ok, ir} = ExDatalog.compile(program)
       iex> length(ir.rules) == 1 and length(ir.relations) == 2
       true
       true

  """
  @spec compile(Program.t()) :: {:ok, ExDatalog.IR.t()} | {:error, [Validator.Error.t()]}
  def compile(%Program{} = program) do
    ExDatalog.Compiler.compile(program)
  end

  def compile({:error, _} = error), do: error

  @doc """
  Evaluates a compiled IR program against a backend engine.

  Returns `{:ok, ExDatalog.Knowledge.t()}` or `{:error, reason}`.

  ## Options

  - `:engine` — backend module (default: `ExDatalog.Engine.Naive`)
  - `:storage` — storage module (default: `ExDatalog.Storage.Map`)
  - `:max_iterations` — fixpoint iteration limit (default: 10_000)
  - `:timeout_ms` — wall-clock timeout in ms (default: 30_000)

  Check `knowledge.stats.termination` for `:fixpoint`, `:iteration_limit`,
  or `:timeout` to determine whether evaluation completed.
  """
  @spec evaluate(ExDatalog.IR.t(), keyword()) :: {:ok, ExDatalog.Knowledge.t()} | {:error, term()}
  def evaluate(%ExDatalog.IR{} = ir, opts \\ []) do
    engine = Keyword.get(opts, :engine, ExDatalog.Engine.Naive)
    engine.evaluate(ir, opts)
  end

  @doc """
  One-shot: validate, compile, and materialize a program.

  Equivalent to `validate/1` → `compile/1` → `evaluate/2`.

  Returns `{:ok, ExDatalog.Knowledge.t()}` or `{:error, reason}`.

  ## Aggregate input types

  Aggregates (`sum`, `min`, `max`) are integer-only. If an aggregate's input
  resolves to a non-integer value at reduction time, evaluation **raises**
  `ArgumentError` rather than returning `{:error, reason}`. A non-integer
  aggregate input is treated as a data-modeling error and surfaces loudly. If
  the input domain is untrusted, constrain it with a type predicate (for example
  `is_integer/1`) earlier in the rule body, or wrap the call in a `try`.

  ## Options

  See `evaluate/2` for available options, plus:

  - `:goal` — `{relation, pattern}` used both as the magic-sets goal
    (when `strategy: :magic_sets`) and as a post-materialization filter
    (default: `nil`). When set, the knowledge base's `relations` map contains
    only the matching tuples for the specified relation. The pattern uses `:_`
    as a wildcard, matching `Knowledge.match/3`.

  ## Examples

       iex> alias ExDatalog.{Program, Rule, Atom, Term}
       iex> program =
       ...>   Program.new()
       ...>   |> Program.add_relation("parent", [:atom, :atom])
       ...>   |> Program.add_fact("parent", [:alice, :bob])
       iex> {:ok, knowledge} = ExDatalog.materialize(program)
       iex> ExDatalog.Knowledge.size(knowledge, "parent")
       1

  """
  @spec materialize(Program.t(), keyword()) ::
          {:ok, ExDatalog.Knowledge.t()} | {:error, [Validator.Error.t()] | term()}
  def materialize(program, opts \\ [])

  def materialize(%Program{} = program, opts) do
    goal = Keyword.get(opts, :goal, nil)

    with {:ok, validated} <- validate(program),
         {:ok, ir} <- ExDatalog.Compiler.compile(validated),
         {:ok, knowledge} <- evaluate(ir, opts) do
      {:ok, apply_goal(knowledge, goal)}
    end
  end

  def materialize({:error, _} = error, _opts), do: error

  defp apply_goal(knowledge, nil), do: knowledge

  defp apply_goal(knowledge, {relation, pattern}) do
    matched = ExDatalog.Knowledge.match(knowledge, relation, pattern)

    %{
      knowledge
      | relations: Map.put(knowledge.relations, relation, matched)
    }
  end
end
