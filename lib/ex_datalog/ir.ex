defmodule ExDatalog.IR do
  @moduledoc """
  Intermediate representation (IR) types for compiled Datalog programs.

  The IR is the engine-neutral output of `ExDatalog.Compiler.compile/1`. It
  contains the same information as a validated `ExDatalog.Program` but in a
  canonical, deterministic form optimized for evaluation:

  - Rules are sorted by `(stratum, relation_name, rule_id)`.
  - Facts are sorted by `(relation_name, values)`.
  - Relations are sorted by name.
  - Each rule carries its assigned `stratum` field.
  - Every struct has a `serialize/1` function that produces a plain map
    suitable for logging, debugging, or future serialisation.

  ## IR Type Hierarchy

      IRProgram
        +-- relations:  [IRRelation]
        +-- facts:      [IRFact]
        +-- rules:      [IRRule]
        +-- strata:     [IRStratum]
        +-- metadata:   map()

      IRRelation   — name, arity, types
      IRFact       — relation, values
      IRRule       — id, head (IRAtom), body ([IRLiteral]), stratum, metadata
      IRLiteral    — {:positive, IRAtom} | {:negative, IRAtom} | {:constraint, IRConstraint}
      IRAtom       — relation, terms ([IRTerm])
      IRTerm       — {:var, name} | {:const, IRValue} | :wildcard
      IRConstraint — op, left, right, result
      IRStratum    — index, rule_ids, relations
      IRValue      — {:int, integer} | {:str, String.t} | {:atom, atom}
      IRType       — :integer | :string | :atom | :any

  """

  @type ir_type :: :integer | :string | :atom | :any

  @type ir_value :: {:int, integer()} | {:str, String.t()} | {:atom, atom()}

  @type ir_term :: {:var, String.t()} | {:const, ir_value()} | :wildcard

  @type ir_constraint :: %ExDatalog.IR.Constraint{
          op: ExDatalog.Constraint.op(),
          left: ir_term(),
          right: ir_term(),
          result: ir_term() | nil
        }

  @type ir_literal ::
          {:positive, ExDatalog.IR.Atom.t()}
          | {:negative, ExDatalog.IR.Atom.t()}
          | {:constraint, ir_constraint()}

  defmodule Relation do
    @moduledoc """
    An IR relation: a named schema with arity and type information.
    """

    @enforce_keys [:name, :arity, :types]
    defstruct [:name, :arity, :types]

    @type t :: %__MODULE__{
            name: String.t(),
            arity: non_neg_integer(),
            types: [ExDatalog.IR.ir_type()]
          }

    @doc """
    Serializes an IRRelation to a plain map.
    """
    @spec serialize(t()) :: map()
    def serialize(%__MODULE__{name: name, arity: arity, types: types}) do
      %{name: name, arity: arity, types: types}
    end
  end

  defmodule Fact do
    @moduledoc """
    An IR fact: a ground tuple asserted as true for a given relation.
    """

    @enforce_keys [:relation, :values]
    defstruct [:relation, :values]

    @type t :: %__MODULE__{
            relation: String.t(),
            values: [ExDatalog.IR.ir_value()]
          }

    @spec serialize(t()) :: map()
    def serialize(%__MODULE__{relation: relation, values: values}) do
      %{relation: relation, values: values}
    end
  end

  defmodule Atom do
    @moduledoc """
    An IR atom: a relation reference with a list of IR terms.
    """

    @enforce_keys [:relation, :terms]
    defstruct [:relation, :terms]

    @type t :: %__MODULE__{
            relation: String.t(),
            terms: [ExDatalog.IR.ir_term()]
          }

    @spec serialize(t()) :: map()
    def serialize(%__MODULE__{relation: relation, terms: terms}) do
      %{relation: relation, terms: terms}
    end
  end

  defmodule Constraint do
    @moduledoc """
    An IR constraint: a comparison or arithmetic predicate.

    Comparison constraints have `result: nil`. Arithmetic constraints have
    `result: {:var, name}`.
    """

    @enforce_keys [:op, :left, :right]
    defstruct [:op, :left, :right, :result]

    @type t :: %__MODULE__{
            op: ExDatalog.Constraint.op(),
            left: ExDatalog.IR.ir_term(),
            right: ExDatalog.IR.ir_term(),
            result: ExDatalog.IR.ir_term() | nil
          }

    @spec serialize(t()) :: map()
    def serialize(%__MODULE__{op: op, left: left, right: right, result: result}) do
      %{op: op, left: left, right: right, result: result}
      |> then(fn m -> if result == nil, do: Map.delete(m, :result), else: m end)
    end
  end

  defmodule Rule do
    @moduledoc """
    An IR rule: a head atom, a body of literals, an assigned stratum, and
    optional metadata.
    """

    @enforce_keys [:id, :head, :body, :stratum]
    defstruct [:id, :head, :body, :stratum, metadata: %{}]

    @type t :: %__MODULE__{
            id: non_neg_integer(),
            head: ExDatalog.IR.Atom.t(),
            body: [ExDatalog.IR.ir_literal()],
            stratum: non_neg_integer(),
            metadata: map()
          }

    @spec serialize(t()) :: map()
    def serialize(%__MODULE__{
          id: id,
          head: head,
          body: body,
          stratum: stratum,
          metadata: metadata
        }) do
      %{
        id: id,
        head: ExDatalog.IR.Atom.serialize(head),
        body:
          Enum.map(body, fn
            {:positive, atom} ->
              %{polarity: :positive, atom: Atom.serialize(atom)}

            {:negative, atom} ->
              %{polarity: :negative, atom: Atom.serialize(atom)}

            {:constraint, c} ->
              %{polarity: :constraint, constraint: Constraint.serialize(c)}
          end),
        stratum: stratum,
        metadata: metadata
      }
    end
  end

  defmodule Stratum do
    @moduledoc """
    An IR stratum: a group of rules and relations that must be evaluated
    together, ordered by stratum index.
    """

    @enforce_keys [:index, :rule_ids, :relations]
    defstruct [:index, :rule_ids, :relations]

    @type t :: %__MODULE__{
            index: non_neg_integer(),
            rule_ids: [non_neg_integer()],
            relations: [String.t()]
          }

    @spec serialize(t()) :: map()
    def serialize(%__MODULE__{index: index, rule_ids: rule_ids, relations: relations}) do
      %{index: index, rule_ids: rule_ids, relations: relations}
    end
  end

  @doc """
  The top-level IR program struct.
  """
  @enforce_keys [:relations, :facts, :rules, :strata]
  defstruct [:relations, :facts, :rules, :strata, metadata: %{}]

  @type t :: %__MODULE__{
          relations: [Relation.t()],
          facts: [Fact.t()],
          rules: [Rule.t()],
          strata: [Stratum.t()],
          metadata: map()
        }

  @doc """
  Serializes an IR program to a plain map.

  The output is deterministic: relations, facts, rules, and strata are
  sorted by their canonical order.
  """
  @spec serialize(t()) :: map()
  def serialize(%__MODULE__{
        relations: relations,
        facts: facts,
        rules: rules,
        strata: strata,
        metadata: metadata
      }) do
    %{
      relations: Enum.map(relations, &Relation.serialize/1),
      facts: Enum.map(facts, &Fact.serialize/1),
      rules: Enum.map(rules, &Rule.serialize/1),
      strata: Enum.map(strata, &Stratum.serialize/1),
      metadata: metadata
    }
  end

  @doc """
  Converts an AST term to an IR term.

  ## Examples

      iex> ExDatalog.IR.from_term({:var, "X"})
      {:var, "X"}

      iex> ExDatalog.IR.from_term({:const, 42})
      {:const, {:int, 42}}

      iex> ExDatalog.IR.from_term({:const, :alice})
      {:const, {:atom, :alice}}

      iex> ExDatalog.IR.from_term({:const, "hello"})
      {:const, {:str, "hello"}}

      iex> ExDatalog.IR.from_term(:wildcard)
      :wildcard

  """
  @spec from_term(ExDatalog.Term.t()) :: ir_term()
  def from_term({:var, name}), do: {:var, name}
  def from_term({:const, value}) when is_integer(value), do: {:const, {:int, value}}
  def from_term({:const, value}) when is_binary(value), do: {:const, {:str, value}}
  def from_term({:const, value}) when is_atom(value), do: {:const, {:atom, value}}
  def from_term(:wildcard), do: :wildcard

  @doc """
  Converts an AST constraint to an IR constraint.
  """
  @spec from_constraint(ExDatalog.Constraint.t()) :: ir_constraint()
  def from_constraint(%ExDatalog.Constraint{op: op, left: left, right: right, result: result}) do
    %Constraint{
      op: op,
      left: from_term(left),
      right: from_term(right),
      result: if(result != nil, do: from_term(result), else: nil)
    }
  end

  @doc """
  Converts an AST atom to an IR atom.
  """
  @spec from_atom(ExDatalog.Atom.t()) :: Atom.t()
  def from_atom(%ExDatalog.Atom{relation: relation, terms: terms}) do
    %Atom{relation: relation, terms: Enum.map(terms, &from_term/1)}
  end
end
