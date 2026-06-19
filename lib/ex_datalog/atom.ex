defmodule ExDatalog.Atom do
  @moduledoc """
  A Datalog atom: a relation reference with a list of terms.

  Atoms appear in rule heads and rule bodies. A head atom names
  the relation being derived. Body atoms name the relations being
  queried or matched.

  An atom does not carry polarity (positive or negative). Polarity
  is expressed at the rule body level via `{:positive, atom}` and
  `{:negative, atom}` literals in `ExDatalog.Rule`.

  ## Examples

      iex> ExDatalog.Atom.new("parent", [{:var, "X"}, {:var, "Y"}])
      %ExDatalog.Atom{relation: "parent", terms: [{:var, "X"}, {:var, "Y"}]}

      iex> ExDatalog.Atom.new("person", [{:const, :alice}])
      %ExDatalog.Atom{relation: "person", terms: [{:const, :alice}]}

  """

  alias ExDatalog.Term

  @type t :: %__MODULE__{
          relation: String.t(),
          terms: [Term.t()]
        }

  @enforce_keys [:relation, :terms]
  defstruct [:relation, :terms]

  @doc """
  Constructs a new atom for the given relation and terms.

  ## Examples

      iex> ExDatalog.Atom.new("edge", [{:var, "X"}, {:var, "Y"}])
      %ExDatalog.Atom{relation: "edge", terms: [{:var, "X"}, {:var, "Y"}]}

      iex> ExDatalog.Atom.new("fact", [{:const, 42}, :wildcard])
      %ExDatalog.Atom{relation: "fact", terms: [{:const, 42}, :wildcard]}

  """
  @spec new(String.t(), [Term.t()]) :: t()
  def new(relation, terms) when is_binary(relation) and is_list(terms) do
    %__MODULE__{relation: relation, terms: terms}
  end

  @doc """
  Returns the arity (number of terms) of the atom.

  ## Examples

      iex> ExDatalog.Atom.arity(ExDatalog.Atom.new("parent", [{:var, "X"}, {:var, "Y"}]))
      2

      iex> ExDatalog.Atom.arity(ExDatalog.Atom.new("node", [{:const, :a}]))
      1

  """
  @spec arity(t()) :: non_neg_integer()
  def arity(%__MODULE__{terms: terms}), do: length(terms)

  @doc """
  Returns all variable names in the atom's terms.

  ## Examples

      iex> ExDatalog.Atom.variables(ExDatalog.Atom.new("parent", [{:var, "X"}, {:const, :alice}, {:var, "Y"}]))
      ["X", "Y"]

      iex> ExDatalog.Atom.variables(ExDatalog.Atom.new("fact", [:wildcard, {:const, 1}]))
      []

  """
  @spec variables(t()) :: [Term.var_name()]
  def variables(%__MODULE__{terms: terms}), do: Term.variables(terms) |> Enum.uniq()

  @doc """
  Returns `true` if the atom is structurally valid.

  Valid means: non-empty relation name, all terms are valid `ExDatalog.Term.t()`.

  ## Examples

      iex> ExDatalog.Atom.valid?(ExDatalog.Atom.new("parent", [{:var, "X"}, {:var, "Y"}]))
      true

      iex> ExDatalog.Atom.valid?(%ExDatalog.Atom{relation: "", terms: [{:var, "X"}]})
      false

      iex> ExDatalog.Atom.valid?(%ExDatalog.Atom{relation: "parent", terms: [:bad]})
      false

  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{relation: rel, terms: terms})
      when is_binary(rel) and byte_size(rel) > 0 and is_list(terms) do
    Enum.all?(terms, &Term.valid?/1)
  end

  def valid?(_), do: false

  @doc """
  Constructs an atom from a shorthand tuple of the form `{relation, terms}`.

  Each term in the list is converted using `Term.from/1`, which follows the
  Prolog convention: uppercase atoms become variables, lowercase atoms and
  other values become constants, and `:_` becomes a wildcard.

  Accepts either a `{relation, terms}` tuple or an existing `%Atom{}` struct
  (passed through unchanged).

  ## Examples

      iex> ExDatalog.Atom.from_tuple({"parent", [:X, :Y]})
      %ExDatalog.Atom{relation: "parent", terms: [{:var, "X"}, {:var, "Y"}]}

      iex> ExDatalog.Atom.from_tuple({"role", [:User, :_ ]})
      %ExDatalog.Atom{relation: "role", terms: [{:var, "User"}, :wildcard]}

      iex> ExDatalog.Atom.from_tuple({"value", [:X, 42]})
      %ExDatalog.Atom{relation: "value", terms: [{:var, "X"}, {:const, 42}]}

  """
  @spec from_tuple({String.t(), [Term.shorthand()]} | t()) :: t()
  def from_tuple({relation, terms}) when is_binary(relation) and is_list(terms) do
    new(relation, Enum.map(terms, &Term.from/1))
  end

  def from_tuple(%__MODULE__{} = atom), do: atom
end
