defmodule ExDatalog.Constraint do
  @moduledoc """
  Built-in predicates: comparisons, arithmetic, type checks, string
  predicates, membership, and extensible constraint evaluation.

  Constraints appear in rule bodies alongside relational atoms. They come in
  several categories:

  - **Comparison constraints** — filter bindings. They do not introduce new
    variable bindings. Both `left` and `right` must be bound before the
    constraint is evaluated. The `result` field is `nil`.

  - **Arithmetic constraints** — bind a new variable. The `result` field names
    the variable that receives the computed value. `left` and `right` must be
    bound; after evaluation `result` is added to the binding environment.

  - **Type predicate constraints** — unary filters that check the Elixir type
    of a bound value. The `right` and `result` fields are `nil`.

  - **String predicate constraints** — binary filters for string operations.
    Both operands must be bound and resolve to binaries. The `result` field
    is `nil`.

  - **Membership constraints** — test whether a value is in a constant list.
    `left` must be bound; `right` is a constant list. The `result` field is
    `nil`.

  ## Extensible evaluation

  The `ExDatalog.Constraint` behaviour defines a `evaluate/3` callback that
  constraint modules implement. Evaluation dispatches based on the constraint's
  `op` field:

  - Comparison ops (`gt`, `lt`, `gte`, `lte`, `eq`, `neq`) dispatch to
    `ExDatalog.Constraints.Comparison`.
  - Arithmetic ops (`add`, `sub`, `mul`, `div`) dispatch to
    `ExDatalog.Constraints.Arithmetic`.
  - Type predicate ops (`is_integer`, `is_binary`, `is_atom`) dispatch to
    `ExDatalog.Constraints.Type`.
  - String predicate ops (`starts_with`, `contains`) dispatch to
    `ExDatalog.Constraints.StringPredicate`.
  - Membership op (`member`) dispatch to
    `ExDatalog.Constraints.Membership`.

  New constraint types require adding the `op` to the relevant category list
  and a dispatch clause in `constraint_module/1` within this module. The
  dispatch is closed (not a runtime registry) to keep evaluation deterministic
  and easily auditable.

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
  | `div/3` | result = div(left, right) (integer division) |

  All arithmetic is **integer-only**. The `:div` operator uses Elixir's
  `Kernel.div/2` (truncating integer division). Division by zero returns
  `:div_by_zero` and filters the binding.

  ## Type predicates

  | Constructor | Meaning |
  |---|---|
  | `type_integer/1` | checks if the bound value is an integer |
  | `type_binary/1` | checks if the bound value is a binary (string) |
  | `type_atom/1` | checks if the bound value is an atom |

  ## String predicates

  | Constructor | Meaning |
  |---|---|
  | `starts_with/2` | String.starts_with?(left, right) |
  | `contains/2` | String.contains?(left, right) |

  ## Membership

  | Constructor | Meaning |
  |---|---|
  | `member/2` | left in right (right is a constant list) |

  ## Examples

      iex> ExDatalog.Constraint.gt({:var, "X"}, {:const, 0})
      %ExDatalog.Constraint{op: :gt, left: {:var, "X"}, right: {:const, 0}, result: nil}

      iex> ExDatalog.Constraint.add({:var, "X"}, {:var, "Y"}, {:var, "Z"})
      %ExDatalog.Constraint{op: :add, left: {:var, "X"}, right: {:var, "Y"}, result: {:var, "Z"}}

      iex> ExDatalog.Constraint.type_integer({:var, "X"})
      %ExDatalog.Constraint{op: :is_integer, left: {:var, "X"}, right: nil, result: nil}

      iex> ExDatalog.Constraint.starts_with({:var, "X"}, {:const, "hello"})
      %ExDatalog.Constraint{op: :starts_with, left: {:var, "X"}, right: {:const, "hello"}, result: nil}

      iex> ExDatalog.Constraint.member({:var, "X"}, {:const, [:a, :b, :c]})
      %ExDatalog.Constraint{op: :member, left: {:var, "X"}, right: {:const, [:a, :b, :c]}, result: nil}

  """

  alias ExDatalog.IR
  alias ExDatalog.Term

  @comparison_ops [:gt, :lt, :gte, :lte, :eq, :neq]
  @arithmetic_ops [:add, :sub, :mul, :div]
  @type_ops [:is_integer, :is_binary, :is_atom]
  @string_ops [:starts_with, :contains]
  @membership_ops [:member]
  @all_ops @comparison_ops ++ @arithmetic_ops ++ @type_ops ++ @string_ops ++ @membership_ops

  @type op ::
          :gt
          | :lt
          | :gte
          | :lte
          | :eq
          | :neq
          | :add
          | :sub
          | :mul
          | :div
          | :is_integer
          | :is_binary
          | :is_atom
          | :starts_with
          | :contains
          | :member

  @type comparison :: %__MODULE__{
          op: :gt | :lt | :gte | :lte | :eq | :neq,
          left: Term.t(),
          right: Term.t(),
          result: nil
        }

  @type arithmetic :: %__MODULE__{
          op: :add | :sub | :mul | :div,
          left: Term.t(),
          right: Term.t(),
          result: {:var, String.t()}
        }

  @type type_predicate :: %__MODULE__{
          op: :is_integer | :is_binary | :is_atom,
          left: Term.t(),
          right: nil,
          result: nil
        }

  @type string_predicate :: %__MODULE__{
          op: :starts_with | :contains,
          left: Term.t(),
          right: Term.t(),
          result: nil
        }

  @type membership :: %__MODULE__{
          op: :member,
          left: Term.t(),
          right: Term.t(),
          result: nil
        }

  @type t :: comparison() | arithmetic() | type_predicate() | string_predicate() | membership()

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
  Constructs an integer division constraint: `result = div(left, right)`.

  Uses truncating integer division (`Kernel.div/2`). Division by zero
  filters the binding (returns `:div_by_zero`).

  ## Examples

      iex> ExDatalog.Constraint.div({:var, "X"}, {:const, 2}, {:var, "Y"})
      %ExDatalog.Constraint{op: :div, left: {:var, "X"}, right: {:const, 2}, result: {:var, "Y"}}

  """
  @spec div(Term.t(), Term.t(), Term.t()) :: t()
  def div(left, right, result), do: arithmetic(:div, left, right, result)

  # --- Type predicate constructors ---

  @doc """
  Constructs an integer type-check constraint.

  Filters bindings where the operand is not an integer. The operand must
  be bound before evaluation.

  ## Examples

      iex> ExDatalog.Constraint.type_integer({:var, "X"})
      %ExDatalog.Constraint{op: :is_integer, left: {:var, "X"}, right: nil, result: nil}

  """
  @spec type_integer(Term.t()) :: t()
  def type_integer(term), do: unary(:is_integer, term)

  @doc """
  Constructs a binary (string) type-check constraint.

  Filters bindings where the operand is not a binary (string). The operand
  must be bound before evaluation.

  ## Examples

      iex> ExDatalog.Constraint.type_binary({:var, "X"})
      %ExDatalog.Constraint{op: :is_binary, left: {:var, "X"}, right: nil, result: nil}

  """
  @spec type_binary(Term.t()) :: t()
  def type_binary(term), do: unary(:is_binary, term)

  @doc """
  Constructs an atom type-check constraint.

  Filters bindings where the operand is not an atom. The operand must be
  bound before evaluation.

  ## Examples

      iex> ExDatalog.Constraint.type_atom({:var, "X"})
      %ExDatalog.Constraint{op: :is_atom, left: {:var, "X"}, right: nil, result: nil}

  """
  @spec type_atom(Term.t()) :: t()
  def type_atom(term), do: unary(:is_atom, term)

  # --- String predicate constructors ---

  @doc """
  Constructs a starts-with constraint: `String.starts_with?(left, right)`.

  Both operands must be bound and resolve to binaries (strings). Returns
  `:filter` if either operand is unbound or not a binary.

  ## Examples

      iex> ExDatalog.Constraint.starts_with({:var, "X"}, {:const, "hello"})
      %ExDatalog.Constraint{op: :starts_with, left: {:var, "X"}, right: {:const, "hello"}, result: nil}

  """
  @spec starts_with(Term.t(), Term.t()) :: t()
  def starts_with(left, right), do: filter(:starts_with, left, right)

  @doc """
  Constructs a contains constraint: `String.contains?(left, right)`.

  Both operands must be bound and resolve to binaries (strings). Returns
  `:filter` if either operand is unbound or not a binary.

  ## Examples

      iex> ExDatalog.Constraint.contains({:var, "X"}, {:const, "ell"})
      %ExDatalog.Constraint{op: :contains, left: {:var, "X"}, right: {:const, "ell"}, result: nil}

  """
  @spec contains(Term.t(), Term.t()) :: t()
  def contains(left, right), do: filter(:contains, left, right)

  # --- Membership constructor ---

  @doc """
  Constructs a membership constraint: `left in right`.

  The `left` operand must be bound. The `right` operand must be a constant
  list (`{:const, list}`). Returns `:filter` if the left value is not
  a member of the right list, or if the left variable is unbound.

  ## Examples

      iex> ExDatalog.Constraint.member({:var, "X"}, {:const, [:a, :b, :c]})
      %ExDatalog.Constraint{op: :member, left: {:var, "X"}, right: {:const, [:a, :b, :c]}, result: nil}

  """
  @spec member(Term.t(), Term.t()) :: t()
  def member(left, right), do: filter(:member, left, right)

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
  Returns `true` if the constraint is a type predicate (unary, filters).

  ## Examples

      iex> ExDatalog.Constraint.type_predicate?(ExDatalog.Constraint.type_integer({:var, "X"}))
      true

      iex> ExDatalog.Constraint.type_predicate?(ExDatalog.Constraint.gt({:var, "X"}, {:const, 0}))
      false

  """
  @spec type_predicate?(t()) :: boolean()
  def type_predicate?(%__MODULE__{op: op}), do: op in @type_ops

  @doc """
  Returns `true` if the constraint is a string predicate (binary, filters).

  ## Examples

      iex> ExDatalog.Constraint.string_predicate?(ExDatalog.Constraint.starts_with({:var, "X"}, {:const, "foo"}))
      true

      iex> ExDatalog.Constraint.string_predicate?(ExDatalog.Constraint.gt({:var, "X"}, {:const, 0}))
      false

  """
  @spec string_predicate?(t()) :: boolean()
  def string_predicate?(%__MODULE__{op: op}), do: op in @string_ops

  @doc """
  Returns `true` if the constraint is a membership test.

  ## Examples

      iex> ExDatalog.Constraint.membership?(ExDatalog.Constraint.member({:var, "X"}, {:const, [:a, :b]}))
      true

      iex> ExDatalog.Constraint.membership?(ExDatalog.Constraint.gt({:var, "X"}, {:const, 0}))
      false

  """
  @spec membership?(t()) :: boolean()
  def membership?(%__MODULE__{op: op}), do: op in @membership_ops

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
    op in @all_ops and Term.valid?(l) and valid_right?(op, r) and valid_result?(op, res)
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
  def input_variables(%__MODULE__{left: left, right: nil}), do: Term.variables([left])

  def input_variables(%__MODULE__{left: left, right: right}), do: Term.variables([left, right])

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
  def result_variable(%__MODULE__{result: _}), do: nil

  # --- Private helpers ---

  defp comparison(op, left, right) do
    %__MODULE__{op: op, left: left, right: right, result: nil}
  end

  defp arithmetic(op, left, right, result) do
    %__MODULE__{op: op, left: left, right: right, result: result}
  end

  defp unary(op, term) do
    %__MODULE__{op: op, left: term, right: nil, result: nil}
  end

  defp filter(op, left, right) do
    %__MODULE__{op: op, left: left, right: right, result: nil}
  end

  defp valid_result?(op, nil)
       when op in @comparison_ops or op in @type_ops or op in @string_ops or op in @membership_ops,
       do: true

  defp valid_result?(op, {:var, name}) when op in @arithmetic_ops,
    do: is_binary(name) and byte_size(name) > 0

  defp valid_result?(_, _), do: false

  defp valid_right?(op, nil) when op in @type_ops, do: true

  defp valid_right?(:member, {:const, value}) when is_list(value), do: true

  defp valid_right?(op, right)
       when op in @comparison_ops or op in @arithmetic_ops or op in @string_ops,
       do: Term.valid?(right)

  defp valid_right?(_, _), do: false

  # --- Extensible constraint behaviour ---

  @doc """
  Evaluates a constraint against a binding environment.

  Accepts either a `%Constraint{}` (public struct) or a
  `%IR.Constraint{}` (compiled form). The IR clause is the hot path used
  by the engine; the public-struct clause converts to IR first, then
  delegates. External callers and tests may use either form.

  Dispatches to the appropriate constraint module based on the constraint's
  `op` field:

  - Comparison ops dispatch to `ExDatalog.Constraints.Comparison`.
  - Arithmetic ops dispatch to `ExDatalog.Constraints.Arithmetic`.
  - Type predicate ops dispatch to `ExDatalog.Constraints.Type`.
  - String predicate ops dispatch to `ExDatalog.Constraints.StringPredicate`.
  - Membership ops dispatch to `ExDatalog.Constraints.Membership`.

  Adding a new constraint type requires adding the `op` to the relevant
  category list and a dispatch clause in `constraint_module/1` — this is
  a closed dispatch, not a runtime registry.

  Returns `{:ok, extended_binding}` if the constraint succeeds (for
  arithmetic, the binding includes the result variable), or `:filter`
  if the constraint fails or an unbound input variable is encountered.

  The `context` parameter carries evaluation metadata (capabilities,
  provenance). For v0.2.0, no constraint implementation reads from the
  context, but it is reserved for future use.

  ## Examples

      iex> c1 = ExDatalog.Constraint.gt({:var, "X"}, {:var, "Y"})
      iex> ExDatalog.Constraint.evaluate(c1, %{"X" => 10, "Y" => 3}, %ExDatalog.Constraint.Context{})
      {:ok, %{"X" => 10, "Y" => 3}}

      iex> c2 = ExDatalog.Constraint.add({:var, "X"}, {:var, "Y"}, {:var, "Z"})
      iex> ExDatalog.Constraint.evaluate(c2, %{"X" => 3, "Y" => 7}, %ExDatalog.Constraint.Context{})
      {:ok, %{"X" => 3, "Y" => 7, "Z" => 10}}

  """
  @callback evaluate(
              constraint :: ExDatalog.IR.Constraint.t(),
              bindings :: ExDatalog.Engine.Binding.t(),
              context :: ExDatalog.Constraint.Context.t()
            ) ::
              {:ok, ExDatalog.Engine.Binding.t()} | :filter

  @spec evaluate(
          t() | ExDatalog.IR.Constraint.t(),
          ExDatalog.Engine.Binding.t(),
          ExDatalog.Constraint.Context.t()
        ) ::
          {:ok, ExDatalog.Engine.Binding.t()} | :filter
  def evaluate(%__MODULE__{} = constraint, binding, context) do
    ir_constraint = IR.from_constraint(constraint)
    evaluate(ir_constraint, binding, context)
  end

  def evaluate(%ExDatalog.IR.Constraint{op: op} = constraint, binding, context) do
    module = constraint_module(op)
    module.evaluate(constraint, binding, context)
  end

  defp constraint_module(op) when op in @comparison_ops, do: ExDatalog.Constraints.Comparison
  defp constraint_module(op) when op in @arithmetic_ops, do: ExDatalog.Constraints.Arithmetic
  defp constraint_module(op) when op in @type_ops, do: ExDatalog.Constraints.Type
  defp constraint_module(op) when op in @string_ops, do: ExDatalog.Constraints.StringPredicate
  defp constraint_module(op) when op in @membership_ops, do: ExDatalog.Constraints.Membership
end
