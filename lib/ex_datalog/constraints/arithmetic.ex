defmodule ExDatalog.Constraints.Arithmetic do
  @moduledoc """
  Arithmetic constraint implementation for the Constraint behaviour.

  Evaluates arithmetic constraints (`:add`, `:sub`, `:mul`, `:div`) which
  bind a result variable. All arithmetic is integer-only. Division by zero
  filters the binding.

  This module is the canonical evaluator for arithmetic operations. It is
  dispatched to by `ExDatalog.Constraint.evaluate/3` when the constraint's
  `op` is `:add`, `:sub`, `:mul`, or `:div`.
  """

  @behaviour ExDatalog.Constraint

  alias ExDatalog.Constraint.Context
  alias ExDatalog.IR

  @impl ExDatalog.Constraint
  @doc """
  Evaluates an arithmetic constraint against a binding environment.

  Accepts an `IR.Constraint` struct as produced by the compiler. Returns
  `{:ok, extended_binding}` when the arithmetic succeeds (result variable
  is bound), or `:filter` when division by zero occurs or an input variable
  is unbound.
  """
  @spec evaluate(IR.Constraint.t(), map(), Context.t()) ::
          {:ok, map()} | :filter
  def evaluate(
        %IR.Constraint{op: op, left: left, right: right, result: result},
        binding,
        _context
      ) do
    with {:ok, left_val} <- IR.resolve_operand(left, binding),
         {:ok, right_val} <- IR.resolve_operand(right, binding) do
      apply_arithmetic(op, left_val, right_val, result, binding)
    else
      :unbound -> :filter
    end
  end

  defp apply_arithmetic(:add, left, right, {:var, name}, binding)
       when is_integer(left) and is_integer(right),
       do: {:ok, Map.put(binding, name, left + right)}

  defp apply_arithmetic(:sub, left, right, {:var, name}, binding)
       when is_integer(left) and is_integer(right),
       do: {:ok, Map.put(binding, name, left - right)}

  defp apply_arithmetic(:mul, left, right, {:var, name}, binding)
       when is_integer(left) and is_integer(right),
       do: {:ok, Map.put(binding, name, left * right)}

  defp apply_arithmetic(:div, _left, 0, {:var, _name}, _binding), do: :filter

  defp apply_arithmetic(:div, left, right, {:var, name}, binding)
       when is_integer(left) and is_integer(right),
       do: {:ok, Map.put(binding, name, div(left, right))}

  defp apply_arithmetic(_op, _left, _right, _result, _binding), do: :filter
end
