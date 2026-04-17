defmodule ExDatalog.Program do
  @moduledoc """
  Builder for constructing Datalog programs.

  A program holds:

  - **Relations** — named schemas with arity and type information.
  - **Facts** — ground tuples asserted as true for a given relation.
  - **Rules** — inference rules that derive new facts from existing ones.

  Programs are built using a pipeline of builder functions. Structural
  validation (arity checking, relation existence) is done at build time by
  `add_relation/3`, `add_fact/3`, and `add_rule/2`. On failure these return
  `{:error, String.t()}` with a human-readable message.

  Semantic validation (variable safety, stratification, constraint binding)
  is done separately by `ExDatalog.Validator.validate/1`, which returns
  `{:error, [ExDatalog.Validator.Errors.t()]}` with structured error structs.

  **Note:** builder methods perform a subset of the same checks as the
  validator (relation existence, arity). This is intentional: the builder
  provides early feedback for interactive construction, while the validator
  is the canonical source of truth and catches issues the builder cannot
  (e.g., programs assembled by directly modifying the struct, which bypasses
  builder validation).

  ## Example

      iex> alias ExDatalog.{Program, Atom, Rule, Term}
      iex> program =
      ...>   Program.new()
      ...>   |> Program.add_relation("parent", [:atom, :atom])
      ...>   |> Program.add_relation("ancestor", [:atom, :atom])
      ...>   |> Program.add_fact("parent", [:alice, :bob])
      ...>   |> Program.add_fact("parent", [:bob, :carol])
      ...>   |> Program.add_rule(
      ...>        Rule.new(
      ...>          Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
      ...>          [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
      ...>        )
      ...>      )
      iex> length(program.facts) == 2
      true
      iex> length(program.rules) == 1
      true

  """

  alias ExDatalog.{Atom, Rule, Term}

  @type relation_name :: String.t()
  @type ir_type :: :integer | :string | :atom | :any
  @type relation_schema :: %{arity: non_neg_integer(), types: [ir_type()]}
  @type fact_values :: [Term.value()]

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

  @doc """
  Adds a ground fact to the program.

  The relation must be declared via `add_relation/3` and the number of
  values must match the relation's arity.

  Returns `{:error, reason}` if:

  - The relation is not defined.
  - The arity of `values` does not match the relation schema.

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
    case Map.fetch(rels, relation) do
      :error ->
        {:error, "relation #{inspect(relation)} is not defined"}

      {:ok, %{arity: arity}} when length(values) != arity ->
        {:error,
         "arity mismatch for relation #{inspect(relation)}: " <>
           "expected #{arity} values, got #{length(values)}"}

      {:ok, _} ->
        %__MODULE__{program | facts: [{relation, values} | program.facts]}
    end
  end

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
      atom =
        case literal do
          {:positive, a} -> a
          {:negative, a} -> a
          other -> {:error, "invalid body literal #{inspect(other)}"}
        end

      case atom do
        {:error, _} = err -> {:halt, err}
        %Atom{} -> {:cont, validate_atom(program, atom)}
        _ -> {:halt, {:error, "invalid body literal #{inspect(literal)}"}}
      end
    end)
  end
end
