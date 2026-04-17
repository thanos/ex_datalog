defmodule ExDatalog.Engine.ConstraintEval do
  @moduledoc """
  Constraint evaluation for Datalog rule bodies.

  Applies IR constraints (comparisons and arithmetic) to binding environments.
  Constraints are processed sequentially in the order they appear in the rule
  body. This sequential evaluation is required because arithmetic constraints
  bind their result variable, making it available to later constraints.

  ## Comparison constraints

  Comparison constraints (`:gt`, `:lt`, `:gte`, `:lte`, `:eq`, `:neq`) are
  filters: they keep or discard the current binding. If the comparison
  evaluates to `false`, the binding is discarded (`:filter`). If `true`, the
  binding passes through unchanged.

  All variables in a comparison constraint must be bound before evaluation.
  If any input variable is unbound, the binding is discarded (`:filter`).

  ## Arithmetic constraints

  Arithmetic constraints (`:add`, `:sub`, `:mul`, `:div`) bind their `result`
  variable. The `left` and `right` operands must be bound; `result` is then
  computed and added to the binding.

  Division by zero returns `:filter` rather than raising.
  """

  alias ExDatalog.Engine.Binding
  alias ExDatalog.IR.Constraint

  @type binding :: Binding.t()

  @doc """
  Applies a list of IR constraints to a binding environment.

  Processes constraints sequentially. A comparison constraint that evaluates
  to `false` discards the binding. An arithmetic constraint extends the binding
  with its result variable.

  Returns `{:ok, final_binding}` if all constraints pass, or `:filter` if any
  comparison fails or an unbound variable is encountered.

  ## Examples

      iex> alias ExDatalog.Engine.ConstraintEval
      iex> alias ExDatalog.IR.Constraint, as: C
      iex> c1 = %C{op: :gt, left: {:var, "X"}, right: {:var, "Y"}, result: nil}
      iex> ConstraintEval.apply([c1], %{"X" => 10, "Y" => 3})
      {:ok, %{"X" => 10, "Y" => 3}}

      iex> ConstraintEval.apply([c1], %{"X" => 3, "Y" => 10})
      :filter

      iex> c2 = %C{op: :add, left: {:var, "X"}, right: {:var, "Y"}, result: {:var, "Z"}}
      iex> ConstraintEval.apply([c2], %{"X" => 3, "Y" => 7})
      {:ok, %{"X" => 3, "Y" => 7, "Z" => 10}}

  """
  @spec apply([Constraint.t()], binding()) :: {:ok, binding()} | :filter
  def apply(constraints, binding) when is_list(constraints) do
    Enum.reduce_while(constraints, {:ok, binding}, fn c, {:ok, b} ->
      case apply_one(c, b) do
        {:ok, new_b} -> {:cont, {:ok, new_b}}
        :filter -> {:halt, :filter}
      end
    end)
  end

  @doc """
  Applies a single IR constraint to a binding environment.

  Returns `{:ok, extended_binding}` for a passing comparison or a successful
  arithmetic binding. Returns `:filter` for a failing comparison, division by
  zero, or an unbound input variable.
  """
  @spec apply_one(Constraint.t(), binding()) :: {:ok, binding()} | :filter
  def apply_one(%Constraint{op: op, left: left, right: right, result: result}, binding) do
    with {:ok, left_val} <- resolve_operand(left, binding),
         {:ok, right_val} <- resolve_operand(right, binding) do
      if comparison_op?(op) do
        apply_comparison(op, left_val, right_val, binding)
      else
        apply_arithmetic(op, left_val, right_val, result, binding)
      end
    else
      :unbound -> :filter
    end
  end

  defp resolve_operand({:var, name}, binding) do
    case Map.fetch(binding, name) do
      {:ok, value} -> {:ok, value}
      :error -> :unbound
    end
  end

  defp resolve_operand({:const, ir_value}, _binding) do
    {:ok, Binding.ir_value_to_native(ir_value)}
  end

  defp resolve_operand(:wildcard, _binding), do: :unbound

  defp comparison_op?(op), do: op in [:gt, :lt, :gte, :lte, :eq, :neq]

  defp apply_comparison(op, left, right, binding) do
    result =
      case op do
        :gt -> left > right
        :lt -> left < right
        :gte -> left >= right
        :lte -> left <= right
        :eq -> left == right
        :neq -> left != right
      end

    if result, do: {:ok, binding}, else: :filter
  end

  defp apply_arithmetic(op, left, right, {:var, result_name}, binding) do
    computed =
      case op do
        :add -> {:ok, left + right}
        :sub -> {:ok, left - right}
        :mul -> {:ok, left * right}
        :div when right == 0 -> :div_by_zero
        :div -> {:ok, div(left, right)}
      end

    case computed do
      {:ok, value} -> {:ok, Map.put(binding, result_name, value)}
      :div_by_zero -> :filter
    end
  end

  defp apply_arithmetic(_op, _left, _right, _result, _binding), do: :filter
end
