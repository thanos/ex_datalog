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

      {:ok, result} =
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
        |> ExDatalog.query()

  ## Pipeline

  The evaluation pipeline is:

  1. `ExDatalog.Program` — builder API
  2. `ExDatalog.Validator` — structural + semantic validation
  3. `ExDatalog.Compiler` — AST to IR
  4. `ExDatalog.Engine` — pluggable evaluation backend
  5. `ExDatalog.Result` — structured result with relation access

  Each step can be invoked individually:

      {:ok, validated} = ExDatalog.validate(program)
      {:ok, ir}        = ExDatalog.compile(program)
      {:ok, result}    = ExDatalog.evaluate(ir, [])

  ## Options

  `query/2` and `evaluate/2` accept:

  - `engine` — backend module (default: `ExDatalog.Engine.Naive`)
  - `storage` — storage module (default: `ExDatalog.Storage.Map`)
  - `max_iterations` — fixpoint iteration limit (default: 10_000)
  - `timeout_ms` — wall-clock timeout in milliseconds (default: 30_000)
  - `goal` — `{relation_name, pattern}` to filter results (default: `nil`)
  - `explain` — enable provenance tracking (default: `false`)
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

  @doc """
  Evaluates a compiled IR program against a backend engine.

  Returns `{:ok, ExDatalog.Result.t()}` or `{:error, reason}`.

  ## Options

  - `:engine` — backend module (default: `ExDatalog.Engine.Naive`)
  - `:storage` — storage module (default: `ExDatalog.Storage.Map`)
  - `:max_iterations` — fixpoint iteration limit (default: 10_000)
  - `:timeout_ms` — wall-clock timeout in ms (default: 30_000)
  """
  @spec evaluate(ExDatalog.IR.t(), keyword()) :: {:ok, ExDatalog.Result.t()} | {:error, term()}
  def evaluate(%ExDatalog.IR{} = ir, opts \\ []) do
    engine = Keyword.get(opts, :engine, ExDatalog.Engine.Naive)
    engine.evaluate(ir, opts)
  end

  @doc """
  One-shot: validate, compile, and evaluate a program.

  Equivalent to `validate/1` → `compile/1` → `evaluate/2`.

  Returns `{:ok, ExDatalog.Result.t()}` or `{:error, reason}`.

  ## Options

  See `evaluate/2` for available options.

  ## Examples

      iex> alias ExDatalog.{Program, Rule, Atom, Term}
      iex> program =
      ...>   Program.new()
      ...>   |> Program.add_relation("parent", [:atom, :atom])
      ...>   |> Program.add_fact("parent", [:alice, :bob])
      iex> {:ok, result} = ExDatalog.query(program)
      iex> ExDatalog.Result.size(result, "parent")
      1

  """
  @spec query(Program.t(), keyword()) ::
          {:ok, ExDatalog.Result.t()} | {:error, [Validator.Error.t()] | term()}
  def query(%Program{} = program, opts \\ []) do
    with {:ok, validated} <- validate(program),
         {:ok, ir} <- ExDatalog.Compiler.compile(validated) do
      evaluate(ir, opts)
    end
  end
end
