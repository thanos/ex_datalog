defmodule ExDatalog.Rule do
  @moduledoc """
  A Datalog rule: `head :- body [, constraints]`.

  A rule consists of:

  - A **head** atom (`ExDatalog.Atom.t()`) — the relation being derived.
  - A **body** list of literals — each is one of:
    - `{:positive, ExDatalog.Atom.t()}` — a positive relational atom.
    - `{:negative, ExDatalog.Atom.t()}` — a negated relational atom.
  - A **constraints** list of `ExDatalog.Constraint.t()` — built-in predicates
    (comparisons and arithmetic) evaluated after joining body atoms.

  Polarity is carried at the rule level, not in the atom itself. Constraints
  are kept separate from the body literal list for clarity and evaluation ordering.

  ## Examples

      iex> alias ExDatalog.{Rule, Atom, Term}
      iex> head = Atom.new("ancestor", [Term.var("X"), Term.var("Y")])
      iex> body = [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
      iex> Rule.new(head, body)
      %ExDatalog.Rule{
        head: %ExDatalog.Atom{relation: "ancestor", terms: [{:var, "X"}, {:var, "Y"}]},
        body: [{:positive, %ExDatalog.Atom{relation: "parent", terms: [{:var, "X"}, {:var, "Y"}]}}],
        constraints: []
      }

  """

  alias ExDatalog.{Atom, Constraint}

  @type literal :: {:positive, Atom.t()} | {:negative, Atom.t()}

  @type t :: %__MODULE__{
          head: Atom.t(),
          body: [literal()],
          constraints: [Constraint.t()]
        }

  defstruct [:head, body: [], constraints: []]

  @doc """
  Constructs a new rule with a head atom and body literals.

  Body literals must be `{:positive, atom}` or `{:negative, atom}` tuples.
  Constraints default to an empty list.

  ## Examples

      iex> alias ExDatalog.{Rule, Atom, Term}
      iex> head = Atom.new("reachable", [Term.var("X"), Term.var("Y")])
      iex> body = [{:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}]
      iex> Rule.new(head, body)
      %ExDatalog.Rule{
        head: %ExDatalog.Atom{relation: "reachable", terms: [{:var, "X"}, {:var, "Y"}]},
        body: [{:positive, %ExDatalog.Atom{relation: "edge", terms: [{:var, "X"}, {:var, "Y"}]}}],
        constraints: []
      }

  """
  @spec new(Atom.t(), [literal()], [Constraint.t()]) :: t()
  def new(%Atom{} = head, body, constraints \\ [])
      when is_list(body) and is_list(constraints) do
    %__MODULE__{head: head, body: body, constraints: constraints}
  end

  @doc """
  Returns all variable names that appear anywhere in the rule
  (head + body + constraints).

  ## Examples

      iex> alias ExDatalog.{Rule, Atom, Term}
      iex> head = Atom.new("ancestor", [Term.var("X"), Term.var("Z")])
      iex> body = [
      ...>   {:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])},
      ...>   {:positive, Atom.new("ancestor", [Term.var("Y"), Term.var("Z")])}
      ...> ]
      iex> rule = Rule.new(head, body)
      iex> Rule.variables(rule) |> Enum.sort()
      ["X", "Y", "Z"]

  """
  @spec variables(t()) :: [String.t()]
  def variables(%__MODULE__{head: head, body: body, constraints: constraints}) do
    head_vars = Atom.variables(head)

    body_vars =
      Enum.flat_map(body, fn
        {:positive, atom} -> Atom.variables(atom)
        {:negative, atom} -> Atom.variables(atom)
      end)

    constraint_vars =
      Enum.flat_map(constraints, fn c ->
        input = Constraint.input_variables(c)
        result = if Constraint.arithmetic?(c), do: [Constraint.result_variable(c)], else: []
        input ++ result
      end)

    (head_vars ++ body_vars ++ constraint_vars) |> Enum.uniq()
  end

  @doc """
  Returns all variable names that appear in the rule head.

  ## Examples

      iex> alias ExDatalog.{Rule, Atom, Term}
      iex> head = Atom.new("ancestor", [Term.var("X"), Term.var("Z")])
      iex> body = [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
      iex> Rule.head_variables(Rule.new(head, body))
      ["X", "Z"]

  """
  @spec head_variables(t()) :: [String.t()]
  def head_variables(%__MODULE__{head: head}), do: Atom.variables(head)

  @doc """
  Returns all variable names that appear in positive body atoms.

  These are the "safe" bindings available for use in the head and constraints.

  ## Examples

      iex> alias ExDatalog.{Rule, Atom, Term}
      iex> head = Atom.new("result", [Term.var("X")])
      iex> body = [
      ...>   {:positive, Atom.new("a", [Term.var("X"), Term.var("Y")])},
      ...>   {:negative, Atom.new("b", [Term.var("Y")])}
      ...> ]
      iex> Rule.positive_body_variables(Rule.new(head, body))
      ["X", "Y"]

  """
  @spec positive_body_variables(t()) :: [String.t()]
  def positive_body_variables(%__MODULE__{body: body}) do
    body
    |> Enum.flat_map(fn
      {:positive, atom} -> Atom.variables(atom)
      {:negative, _} -> []
    end)
    |> Enum.uniq()
  end

  @doc """
  Returns all body atoms (stripping polarity).

  ## Examples

      iex> alias ExDatalog.{Rule, Atom, Term}
      iex> a1 = Atom.new("parent", [Term.var("X"), Term.var("Y")])
      iex> a2 = Atom.new("alive", [Term.var("X")])
      iex> rule = Rule.new(Atom.new("ok", [Term.var("X")]), [{:positive, a1}, {:negative, a2}])
      iex> Rule.body_atoms(rule)
      [
        %ExDatalog.Atom{relation: "parent", terms: [{:var, "X"}, {:var, "Y"}]},
        %ExDatalog.Atom{relation: "alive", terms: [{:var, "X"}]}
      ]

  """
  @spec body_atoms(t()) :: [Atom.t()]
  def body_atoms(%__MODULE__{body: body}) do
    Enum.map(body, fn
      {:positive, atom} -> atom
      {:negative, atom} -> atom
    end)
  end

  @doc """
  Returns `true` if the rule contains any negative body literals.

  ## Examples

      iex> alias ExDatalog.{Rule, Atom, Term}
      iex> head = Atom.new("bachelor", [Term.var("X")])
      iex> body = [
      ...>   {:positive, Atom.new("male", [Term.var("X")])},
      ...>   {:negative, Atom.new("married", [Term.var("X"), :wildcard])}
      ...> ]
      iex> Rule.has_negation?(Rule.new(head, body))
      true

      iex> alias ExDatalog.{Rule, Atom, Term}
      iex> Rule.has_negation?(Rule.new(
      ...>   Atom.new("r", [Term.var("X")]),
      ...>   [{:positive, Atom.new("s", [Term.var("X")])}]
      ...> ))
      false

  """
  @spec has_negation?(t()) :: boolean()
  def has_negation?(%__MODULE__{body: body}) do
    Enum.any?(body, fn
      {:negative, _} -> true
      _ -> false
    end)
  end
end
