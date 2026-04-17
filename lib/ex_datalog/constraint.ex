defmodule ExDatalog.Constraint do
  @moduledoc """
  Built-in predicates: comparisons and arithmetic.

  Constraints appear in rule bodies alongside relational atoms. They come in
  two categories:

  - **Comparison constraints** — filter bindings. They do not introduce new
    variable bindings. Both `left` and `right` must be bound before the
    constraint is evaluated. The `result` field is `nil`.

  - **Arithmetic constraints** — bind a new variable. The `result` field names
    the variable that receives the computed value. `left` and `right` must be
    bound; after evaluation `result` is added to the binding environment.

  ## Comparison operators

  | Constructor | Meaning |
  |---|---|
  | `gt/2` | left > right |
  | `lt/2` | left < right |
  | `gte/2` | left >= right |
  | `lte/2` | left <= right |
  | `eq/2` | left == right |
  | `neq/2` | left != right |

  ## Arithmetic operators

  | Constructor | Meaning |
  |---|---|
  | `add/3` | result = left + right |
  | `sub/3` | result = left - right |
  | `mul/3` | result = left * right |
  | `div/3` | result = left / right |

  ## Examples

      iex> ExDatalog.Constraint.gt({:var, "X"}, {:const, 0})
      %ExDatalog.Constraint{op: :gt, left: {:var, "X"}, right: {:const, 0}, result: nil}

      iex> ExDatalog.Constraint.add({:var, "X"}, {:var, "Y"}, {:var, "Z"})
      %ExDatalog.Constraint{op: :add, left: {:var, "X"}, right: {:var, "Y"}, result: {:var, "Z"}}

  """

  alias ExDatalog.Term

  @comparison_ops [:gt, :lt, :gte, :lte, :eq, :neq]
  @arithmetic_ops [:add, :sub, :mul, :div]
  @all_ops @comparison_ops ++ @arithmetic_ops

  @type op :: :gt | :lt | :gte | :lte | :eq | :neq | :add | :sub | :mul | :div
  @type t :: %__MODULE__{
          op: op(),
          left: Term.t(),
          right: Term.t(),
          result: Term.t() | nil
        }

  defstruct [:op, :left, :right, :result]

  # --- Comparison constructors ---

  @doc """
  Constructs a greater-than constraint: `left > right`.

  ## Examples

      iex> ExDatalog.Constraint.gt({:var, "A"}, {:const, 5})
      %ExDatalog.Constraint{op: :gt, left: {:var, "A"}, right: {:const, 5}, result: nil}

  """
  @spec gt(Term.t(), Term.t()) :: t()
  def gt(left, right), do: comparison(:gt, left, right)

  @doc """
  Constructs a less-than constraint: `left < right`.

  ## Examples

      iex> ExDatalog.Constraint.lt({:var, "A"}, {:const, 10})
      %ExDatalog.Constraint{op: :lt, left: {:var, "A"}, right: {:const, 10}, result: nil}

  """
  @spec lt(Term.t(), Term.t()) :: t()
  def lt(left, right), do: comparison(:lt, left, right)

  @doc """
  Constructs a greater-than-or-equal constraint: `left >= right`.

  ## Examples

      iex> ExDatalog.Constraint.gte({:var, "A"}, {:const, 0})
      %ExDatalog.Constraint{op: :gte, left: {:var, "A"}, right: {:const, 0}, result: nil}

  """
  @spec gte(Term.t(), Term.t()) :: t()
  def gte(left, right), do: comparison(:gte, left, right)

  @doc """
  Constructs a less-than-or-equal constraint: `left <= right`.

  ## Examples

      iex> ExDatalog.Constraint.lte({:var, "A"}, {:const, 100})
      %ExDatalog.Constraint{op: :lte, left: {:var, "A"}, right: {:const, 100}, result: nil}

  """
  @spec lte(Term.t(), Term.t()) :: t()
  def lte(left, right), do: comparison(:lte, left, right)

  @doc """
  Constructs an equality constraint: `left == right`.

  ## Examples

      iex> ExDatalog.Constraint.eq({:var, "X"}, {:const, :alice})
      %ExDatalog.Constraint{op: :eq, left: {:var, "X"}, right: {:const, :alice}, result: nil}

  """
  @spec eq(Term.t(), Term.t()) :: t()
  def eq(left, right), do: comparison(:eq, left, right)

  @doc """
  Constructs an inequality constraint: `left != right`.

  ## Examples

      iex> ExDatalog.Constraint.neq({:var, "X"}, {:var, "Y"})
      %ExDatalog.Constraint{op: :neq, left: {:var, "X"}, right: {:var, "Y"}, result: nil}

  """
  @spec neq(Term.t(), Term.t()) :: t()
  def neq(left, right), do: comparison(:neq, left, right)

  # --- Arithmetic constructors ---

  @doc """
  Constructs an addition constraint: `result = left + right`.

  ## Examples

      iex> ExDatalog.Constraint.add({:var, "X"}, {:var, "Y"}, {:var, "Z"})
      %ExDatalog.Constraint{op: :add, left: {:var, "X"}, right: {:var, "Y"}, result: {:var, "Z"}}

  """
  @spec add(Term.t(), Term.t(), Term.t()) :: t()
  def add(left, right, result), do: arithmetic(:add, left, right, result)

  @doc """
  Constructs a subtraction constraint: `result = left - right`.

  ## Examples

      iex> ExDatalog.Constraint.sub({:var, "X"}, {:const, 1}, {:var, "Y"})
      %ExDatalog.Constraint{op: :sub, left: {:var, "X"}, right: {:const, 1}, result: {:var, "Y"}}

  """
  @spec sub(Term.t(), Term.t(), Term.t()) :: t()
  def sub(left, right, result), do: arithmetic(:sub, left, right, result)

  @doc """
  Constructs a multiplication constraint: `result = left * right`.

  ## Examples

      iex> ExDatalog.Constraint.mul({:var, "X"}, {:const, 2}, {:var, "Y"})
      %ExDatalog.Constraint{op: :mul, left: {:var, "X"}, right: {:const, 2}, result: {:var, "Y"}}

  """
  @spec mul(Term.t(), Term.t(), Term.t()) :: t()
  def mul(left, right, result), do: arithmetic(:mul, left, right, result)

  @doc """
  Constructs a division constraint: `result = left / right`.

  ## Examples

      iex> ExDatalog.Constraint.div({:var, "X"}, {:const, 2}, {:var, "Y"})
      %ExDatalog.Constraint{op: :div, left: {:var, "X"}, right: {:const, 2}, result: {:var, "Y"}}

  """
  @spec div(Term.t(), Term.t(), Term.t()) :: t()
  def div(left, right, result), do: arithmetic(:div, left, right, result)

  # --- Introspection ---

  @doc """
  Returns `true` if the constraint is a comparison (filters, does not bind).

  ## Examples

      iex> ExDatalog.Constraint.comparison?(ExDatalog.Constraint.gt({:var, "X"}, {:const, 0}))
      true

      iex> ExDatalog.Constraint.comparison?(ExDatalog.Constraint.add({:var, "X"}, {:var, "Y"}, {:var, "Z"}))
      false

  """
  @spec comparison?(t()) :: boolean()
  def comparison?(%__MODULE__{op: op}), do: op in @comparison_ops

  @doc """
  Returns `true` if the constraint is arithmetic (binds a result variable).

  ## Examples

      iex> ExDatalog.Constraint.arithmetic?(ExDatalog.Constraint.add({:var, "X"}, {:var, "Y"}, {:var, "Z"}))
      true

      iex> ExDatalog.Constraint.arithmetic?(ExDatalog.Constraint.lt({:var, "X"}, {:const, 5}))
      false

  """
  @spec arithmetic?(t()) :: boolean()
  def arithmetic?(%__MODULE__{op: op}), do: op in @arithmetic_ops

  @doc """
  Returns `true` if the constraint is structurally valid.

  ## Examples

      iex> ExDatalog.Constraint.valid?(ExDatalog.Constraint.gt({:var, "X"}, {:const, 0}))
      true

      iex> ExDatalog.Constraint.valid?(%ExDatalog.Constraint{op: :bad, left: {:var, "X"}, right: {:const, 0}, result: nil})
      false

  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{op: op, left: l, right: r, result: res}) do
    op in @all_ops and Term.valid?(l) and Term.valid?(r) and valid_result?(op, res)
  end

  def valid?(_), do: false

  @doc """
  Returns all input variable names referenced by the constraint.

  These are the variables that must be bound before the constraint is evaluated.

  ## Examples

      iex> ExDatalog.Constraint.input_variables(ExDatalog.Constraint.gt({:var, "X"}, {:var, "Y"}))
      ["X", "Y"]

      iex> ExDatalog.Constraint.input_variables(ExDatalog.Constraint.add({:var, "A"}, {:const, 1}, {:var, "B"}))
      ["A"]

  """
  @spec input_variables(t()) :: [Term.var_name()]
  def input_variables(%__MODULE__{left: left, right: right}) do
    Term.variables([left, right])
  end

  @doc """
  Returns the result variable name for an arithmetic constraint, or `nil` for comparisons.

  ## Examples

      iex> ExDatalog.Constraint.result_variable(ExDatalog.Constraint.add({:var, "X"}, {:var, "Y"}, {:var, "Z"}))
      "Z"

      iex> ExDatalog.Constraint.result_variable(ExDatalog.Constraint.gt({:var, "X"}, {:const, 0}))
      nil

  """
  @spec result_variable(t()) :: Term.var_name() | nil
  def result_variable(%__MODULE__{result: {:var, name}}), do: name
  def result_variable(%__MODULE__{result: nil}), do: nil

  # --- Private helpers ---

  defp comparison(op, left, right) do
    %__MODULE__{op: op, left: left, right: right, result: nil}
  end

  defp arithmetic(op, left, right, result) do
    %__MODULE__{op: op, left: left, right: right, result: result}
  end

  defp valid_result?(op, nil) when op in @comparison_ops, do: true

  defp valid_result?(op, {:var, name}) when op in @arithmetic_ops,
    do: is_binary(name) and byte_size(name) > 0

  defp valid_result?(_, _), do: false
end
