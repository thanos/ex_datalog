defmodule ExDatalog.Program do
  @moduledoc """
  Builder for constructing Datalog programs.

  A program holds:

  - **Relations** — named schemas with arity and type information.
  - **Facts** — ground tuples asserted as true for a given relation.
  - **Rules** — inference rules that derive new facts from existing ones.

  Relation names are string keys stored in a map. They do not collide with
  internal atoms like `:positive`, `:negative`, `:wildcard`, or `:constraint`
  because those atoms appear in tuple positions (`{:positive, atom}`),
  not as map keys.

  Programs are built using a pipeline of builder functions. Structural
  validation (arity checking, relation existence) is done at build time by
  `add_relation/3`, `add_fact/3`, and `add_rule/2`. On failure these return
  `{:error, String.t()}` with a human-readable message.

  ## Error propagation in pipelines

  Because builder functions return `t() | {:error, String.t()}`, a failed
  step will short-circuit the rest of the pipeline: the `{:error, _}` tuple
  passes through unchanged. This means you can pipe freely and check for
  errors at the end:

      {:ok, knowledge} =
        Program.new()
        |> Program.add_relation("edge", [:atom, :atom])
        |> Program.add_relation("path", [:atom, :atom])
        |> Program.add_fact("edge", [:a, :b])
        |> Program.add_rule({"path", [:X, :Y]}, [{:positive, {"edge", [:X, :Y]}}])
        |> ExDatalog.materialize()

  If `add_relation/3` fails, the `{:error, msg}` tuple flows through
  `add_fact/3` and `add_rule/3` without raising, and `ExDatalog.materialize/1`
  will detect the error struct and return `{:error, [msg]}`.

  Semantic validation (variable safety, stratification, constraint binding)
  is done separately by `ExDatalog.Validator.validate/1`, which returns
  `{:error, [ExDatalog.Validator.Error.t()]}` with structured error structs.

  **Note:** builder methods perform a subset of the same checks as the
  validator (relation existence, arity). This is intentional: the builder
  provides early feedback for interactive construction, while the validator
  is the canonical source of truth and catches issues the builder cannot
  (e.g., programs assembled by directly modifying the struct, which bypasses
  builder validation).

  ## Shorthand rule notation

  `add_rule/3` and `add_rule/4` accept a more ergonomic tuple-based notation
  that avoids the need for explicit `Rule.new/3`, `ExDatalog.Atom.new/2`, and
  `Term.var/1` calls:

  - **Head** — `{"relation", [terms...]}` where each term follows the
    Prolog convention: uppercase atoms become variables (`:X` → `{:var, "X"}`),
    `:_` becomes a wildcard, lowercase atoms and other values become constants.

  - **Body** — `{:positive, {"rel", [terms...]}}` or
    `{:negative, {"rel", [terms...]}}` for each literal.

  - **Constraints** — operator tuples like `{:neq, :A, :B}` for comparisons,
    `{:add, :X, :Y, :Z}` for arithmetic, `{:is_integer, :V}` for type
    predicates, `{:starts_with, :E, "prefix"}` for string predicates, and
    `{:member, :X, [:a, :b]}` for membership.

      Program.add_rule(program,
        {"ancestor", [:X, :Z]},
        [
          {:positive, {"parent", [:X, :Y]}},
          {:positive, {"ancestor", [:Y, :Z]}}
        ]
      )

      Program.add_rule(program,
        {"high_earner", [:X]},
        [{:positive, {"income", [:X, :S]}}],
        [{:gt, :S, 100_000}]
      )

  The struct-based `add_rule/2` remains available for cases where you need
  full control over term types.

  ## Example

      iex> alias ExDatalog.{Program, Atom, Rule, Term}
      iex> program =
      ...>   Program.new()
      ...>   |> Program.add_relation("parent", [:atom, :atom])
      ...>   |> Program.add_relation("ancestor", [:atom, :atom])
      ...>   |> Program.add_fact("parent", [:alice, :bob])
      ...>   |> Program.add_fact("parent", [:bob, :carol])
      ...>   |> Program.add_rule(
      ...>        {"ancestor", [:X, :Y]},
      ...>        [{:positive, {"parent", [:X, :Y]}}]
      ...>      )
      iex> length(program.facts) == 2
      true
      iex> length(program.rules) == 1
      true

  """

  alias ExDatalog.{Atom, Constraint, Rule, Term}

  @type relation_name :: String.t()
  @type ir_type :: :integer | :string | :atom | :any
  @type relation_schema :: %{arity: non_neg_integer(), types: [ir_type()]}
  @type fact_values :: [Term.value()]

  @type head_shorthand :: {String.t(), [Term.shorthand()]} | Atom.t()
  @type body_literal_shorthand ::
          {:positive | :negative, {String.t(), [Term.shorthand()]}}
          | {:positive | :negative, Atom.t()}
          | Rule.literal()
  @type constraint_shorthand :: tuple() | Constraint.t()

  @type t :: %__MODULE__{
          relations: %{relation_name() => relation_schema()},
          facts: [{relation_name(), fact_values()}],
          rules: [Rule.t()]
        }

  defstruct relations: %{}, facts: [], rules: []

  @doc """
  Creates a new, empty Datalog program.

  ## Examples

      iex> ExDatalog.Program.new()
      %ExDatalog.Program{relations: %{}, facts: [], rules: []}

  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Adds a relation schema to the program.

  `types` is a list of type atoms (`:integer`, `:string`, `:atom`, `:any`)
  with length equal to the arity of the relation.

  Returns `{:error, reason}` if:

  - `name` is empty.
  - `types` is empty.
  - The relation already exists.

  ## Examples

      iex> ExDatalog.Program.add_relation(ExDatalog.Program.new(), "parent", [:atom, :atom])
      %ExDatalog.Program{
        relations: %{"parent" => %{arity: 2, types: [:atom, :atom]}},
        facts: [],
        rules: []
      }

      iex> {:error, _} = ExDatalog.Program.add_relation(ExDatalog.Program.new(), "", [:atom])
      {:error, "relation name must be a non-empty string"}

  """
  @spec add_relation(t(), relation_name(), [ir_type()]) :: t() | {:error, String.t()}
  def add_relation(%__MODULE__{} = _program, name, _types)
      when not is_binary(name) or byte_size(name) == 0 do
    {:error, "relation name must be a non-empty string"}
  end

  def add_relation(%__MODULE__{} = _program, _name, types)
      when not is_list(types) or types == [] do
    {:error, "types must be a non-empty list"}
  end

  def add_relation(%__MODULE__{relations: rels} = program, name, types) do
    if Map.has_key?(rels, name) do
      {:error, "relation #{inspect(name)} already defined"}
    else
      schema = %{arity: length(types), types: types}
      %__MODULE__{program | relations: Map.put(rels, name, schema)}
    end
  end

  def add_relation({:error, _} = err, _name, _types), do: err

  @doc """
  Adds a ground fact to the program.

  The relation must be declared via `add_relation/3` and the number of
  values must match the relation's arity.

  Returns `{:error, reason}` if:

  - The relation is not defined.
  - The arity of `values` does not match the relation schema.
  - A value in `values` is not an integer, string, or atom (floats are not supported).

  ## Examples

      iex> alias ExDatalog.Program
      iex> program = Program.new() |> Program.add_relation("parent", [:atom, :atom])
      iex> Program.add_fact(program, "parent", [:alice, :bob])
      %ExDatalog.Program{
        relations: %{"parent" => %{arity: 2, types: [:atom, :atom]}},
        facts: [{"parent", [:alice, :bob]}],
        rules: []
      }

      iex> alias ExDatalog.Program
      iex> program = Program.new() |> Program.add_relation("parent", [:atom, :atom])
      iex> {:error, _} = Program.add_fact(program, "unknown", [:alice])
      {:error, "relation \\"unknown\\" is not defined"}

  """
  @spec add_fact(t(), relation_name(), fact_values()) :: t() | {:error, String.t()}
  def add_fact(%__MODULE__{relations: rels} = program, relation, values)
      when is_binary(relation) and is_list(values) do
    with :ok <- validate_fact_values(values),
         {:ok, %{arity: arity}} <- Map.fetch(rels, relation) do
      if length(values) != arity do
        {:error,
         "arity mismatch for relation #{inspect(relation)}: " <>
           "expected #{arity} values, got #{length(values)}"}
      else
        %__MODULE__{program | facts: [{relation, values} | program.facts]}
      end
    else
      :error ->
        {:error, "relation #{inspect(relation)} is not defined"}

      {:error, _} = err ->
        err
    end
  end

  def add_fact({:error, _} = err, _relation, _values), do: err

  @doc """
  Adds a fact to the program from a `{relation, values}` tuple.

  This is the tuple form produced by Schema relation constructors
  (e.g., `MySchema.emp(:alice, :eng)` returns `{"emp", [:alice, :eng]}`).

  ## Examples

      iex> alias ExDatalog.Program
      iex> program = Program.new() |> Program.add_relation("emp", [:atom, :atom])
      iex> program = Program.add_fact(program, {"emp", [:alice, :eng]})
      iex> program.facts
      [{"emp", [:alice, :eng]}]
  """
  @spec add_fact(t(), {String.t(), [term()]}) :: t() | {:error, term()}
  def add_fact(program, {relation, values}) when is_binary(relation) and is_list(values) do
    add_fact(program, relation, values)
  end

  def add_fact({:error, _} = err, {_relation, _values}), do: err

  @doc """
  Adds multiple facts to the program from a list of `{relation, values}` tuples.

  ## Examples

      iex> alias ExDatalog.Program
      iex> program = Program.new() |> Program.add_relation("emp", [:atom, :atom])
      iex> facts = [{"emp", [:alice, :eng]}, {"emp", [:bob, :eng]}]
      iex> program = Program.add_facts(program, facts)
      iex> length(program.facts)
      2
  """
  @spec add_facts(t(), [{String.t(), [term()]}]) :: t() | {:error, term()}
  def add_facts(program, facts) when is_list(facts) do
    Enum.reduce_while(facts, program, fn fact, acc ->
      case add_fact(acc, fact) do
        {:error, _} = err -> {:halt, err}
        prog -> {:cont, prog}
      end
    end)
  end

  def add_facts({:error, _} = err, _facts), do: err

  @doc """
  Materializes the program. A pipe-friendly convenience for
  `ExDatalog.materialize/2`.

  ## Examples

      iex> alias ExDatalog.{Program, Knowledge}
      iex> program = Program.new() |> Program.add_relation("edge", [:atom, :atom])
      iex> program = program |> Program.add_fact("edge", [:a, :b])
      iex> {:ok, knowledge} = Program.materialize(program)
      iex> Knowledge.get(knowledge, "edge") |> MapSet.to_list()
      [{:a, :b}]
  """
  @spec materialize(t(), keyword()) :: {:ok, ExDatalog.Knowledge.t()} | {:error, term()}
  def materialize(program, opts \\ [])

  def materialize(%__MODULE__{} = program, opts) do
    ExDatalog.materialize(program, opts)
  end

  def materialize({:error, _} = err, _opts), do: err

  @doc """
  Adds a rule to the program.

  Performs structural validation:

  - The head relation must be declared.
  - The head arity must match the relation schema.
  - All body atoms must reference declared relations with matching arities.

  Semantic validation (variable safety, stratification) is deferred to
  `ExDatalog.Validator`.

  Returns `{:error, reason}` if any structural check fails.

  ## Examples

      iex> alias ExDatalog.{Program, Rule, Atom, Term}
      iex> program =
      ...>   Program.new()
      ...>   |> Program.add_relation("parent", [:atom, :atom])
      ...>   |> Program.add_relation("ancestor", [:atom, :atom])
      iex> rule = Rule.new(
      ...>   Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
      ...>   [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
      ...> )
      iex> result = Program.add_rule(program, rule)
      iex> length(result.rules) == 1
      true

  """
  @spec add_rule(t(), Rule.t()) :: t() | {:error, String.t()}
  def add_rule(%__MODULE__{} = program, %Rule{} = rule) do
    with :ok <- validate_atom(program, rule.head),
         :ok <- validate_body(program, rule.body) do
      %__MODULE__{program | rules: [rule | program.rules]}
    end
  end

  def add_rule({:error, _} = err, %Rule{}), do: err

  @doc """
  Adds a rule using shorthand notation for the head atom, body literals,
  and constraints.

  This is a more ergonomic alternative to `add_rule/2` that avoids the need
  for explicit `Rule.new/3`, `ExDatalog.Atom.new/2`, and `ExDatalog.Term.var/1` calls.

  The **head** is a tuple `{"relation", [terms...]}` where each term follows
  the Prolog-inspired convention:

  - Uppercase atoms become logic variables (`:X` → `{:var, "X"}`)
  - `:_` becomes a wildcard
  - Lowercase atoms and other values become constants

  Each **body literal** is `{:positive, {"rel", [terms...]}}` or
  `{:negative, {"rel", [terms...]}}`. You may also mix in structs like
  `{:positive, ExDatalog.Atom.new(...)}`.

  Each **constraint** is an operator tuple like `{:neq, :A, :B}` or
  `{:add, :X, :Y, :Z}`. You may also use existing `%Constraint{}` structs.

  Returns `{:error, reason}` if any structural check fails (same validation
  as `add_rule/2`).

  ## Examples

      iex> alias ExDatalog.Program
      iex> program =
      ...>   Program.new()
      ...>   |> Program.add_relation("parent", [:atom, :atom])
      ...>   |> Program.add_relation("ancestor", [:atom, :atom])
      iex> result = Program.add_rule(program,
      ...>   {"ancestor", [:X, :Y]},
      ...>   [{:positive, {"parent", [:X, :Y]}}]
      ...> )
      iex> length(result.rules) == 1
      true

      iex> alias ExDatalog.Program
      iex> program =
      ...>   Program.new()
      ...>   |> Program.add_relation("income", [:atom, :integer])
      ...>   |> Program.add_relation("high_earner", [:atom])
      iex> result = Program.add_rule(program,
      ...>   {"high_earner", [:X]},
      ...>   [{:positive, {"income", [:X, :S]}}],
      ...>   [{:gt, :S, 100_000}]
      ...> )
      iex> length(result.rules) == 1
      true

  """
  @spec add_rule(t(), head_shorthand(), [body_literal_shorthand()], [constraint_shorthand()]) ::
          t() | {:error, String.t()}
  def add_rule(program, head, body, constraints \\ [])

  def add_rule(%__MODULE__{} = program, head, body, constraints)
      when is_list(body) and is_list(constraints) do
    rule =
      Rule.new(
        Atom.from_tuple(head),
        Enum.map(body, &body_literal_from_tuple/1),
        Enum.map(constraints, &Constraint.from_tuple/1)
      )

    add_rule(program, rule)
  end

  def add_rule({:error, _} = err, _head, _body, _constraints), do: err

  @doc """
  Returns the schema for a relation, or `nil` if not defined.

  ## Examples

      iex> alias ExDatalog.Program
      iex> program = Program.new() |> Program.add_relation("parent", [:atom, :atom])
      iex> Program.relation(program, "parent")
      %{arity: 2, types: [:atom, :atom]}

      iex> alias ExDatalog.Program
      iex> Program.relation(Program.new(), "unknown")
      nil

  """
  @spec relation(t(), relation_name()) :: relation_schema() | nil
  def relation(%__MODULE__{relations: rels}, name), do: Map.get(rels, name)

  @doc """
  Returns `true` if the relation is defined in the program.

  ## Examples

      iex> alias ExDatalog.Program
      iex> program = Program.new() |> Program.add_relation("parent", [:atom, :atom])
      iex> Program.has_relation?(program, "parent")
      true

      iex> alias ExDatalog.Program
      iex> Program.has_relation?(Program.new(), "unknown")
      false

  """
  @spec has_relation?(t(), relation_name()) :: boolean()
  def has_relation?(%__MODULE__{relations: rels}, name), do: Map.has_key?(rels, name)

  # --- Private helpers ---

  defp body_literal_from_tuple({polarity, {_, _} = atom_tuple})
       when polarity in [:positive, :negative] do
    {polarity, Atom.from_tuple(atom_tuple)}
  end

  defp body_literal_from_tuple({polarity, %Atom{} = atom})
       when polarity in [:positive, :negative] do
    {polarity, atom}
  end

  defp validate_atom(program, atom) do
    with :ok <- validate_atom_relation(atom, program),
         :ok <- validate_atom_arity(atom, program),
         :ok <- validate_atom_terms(atom) do
      :ok
    end
  end

  defp validate_atom_relation(%Atom{relation: rel}, %__MODULE__{relations: rels}) do
    if Map.has_key?(rels, rel) do
      :ok
    else
      {:error, "atom references undefined relation #{inspect(rel)}"}
    end
  end

  defp validate_atom_arity(%Atom{relation: rel, terms: terms}, %__MODULE__{relations: rels}) do
    case Map.fetch(rels, rel) do
      {:ok, %{arity: arity}} when length(terms) != arity ->
        {:error,
         "arity mismatch for relation #{inspect(rel)}: " <>
           "expected #{arity} terms, got #{length(terms)}"}

      _ ->
        :ok
    end
  end

  defp validate_atom_terms(%Atom{relation: rel, terms: terms}) do
    case Enum.find(terms, fn t -> not Term.valid?(t) end) do
      nil -> :ok
      bad -> {:error, "invalid term #{inspect(bad)} in atom for relation #{inspect(rel)}"}
    end
  end

  defp validate_body(program, body) do
    Enum.reduce_while(body, :ok, fn literal, :ok ->
      case literal do
        {:callback, %ExDatalog.Callback{}} ->
          {:cont, :ok}

        {:positive, %Atom{} = a} ->
          {:cont, validate_atom(program, a)}

        {:negative, %Atom{} = a} ->
          {:cont, validate_atom(program, a)}

        other ->
          {:halt, {:error, "invalid body literal #{inspect(other)}"}}
      end
    end)
  end

  defp validate_fact_values(values) do
    case Enum.find(values, fn v -> not valid_fact_value?(v) end) do
      nil -> :ok
      v when is_float(v) -> {:error, "float values are not supported: #{inspect(v)}"}
      v -> {:error, "unsupported fact value: #{inspect(v)} (expected integer, string, or atom)"}
    end
  end

  defp valid_fact_value?(v) when is_integer(v), do: true
  defp valid_fact_value?(v) when is_binary(v), do: true
  defp valid_fact_value?(v) when is_atom(v), do: true
  defp valid_fact_value?(_), do: false
end
