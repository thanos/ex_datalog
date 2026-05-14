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
  alias ExDatalog.IR.Constraint

  @impl ExDatalog.Constraint
  @doc """
  Evaluates an arithmetic constraint against a binding environment.

  Accepts an `IR.Constraint` struct as produced by the compiler. Returns
  `{:ok, extended_binding}` when the arithmetic succeeds (result variable
  is bound), or `:filter` when division by zero occurs or an input variable
  is unbound.
  """
  @spec evaluate(Constraint.t(), map(), Context.t()) ::
          {:ok, map()} | :filter
  def evaluate(%Constraint{op: op, left: left, right: right, result: result}, binding, _context) do
    with {:ok, left_val} <- resolve_operand(left, binding),
         {:ok, right_val} <- resolve_operand(right, binding) do
      apply_arithmetic(op, left_val, right_val, result, binding)
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
    {:ok, ir_value_to_native(ir_value)}
  end

  defp resolve_operand(:wildcard, _binding), do: :unbound

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

  defp ir_value_to_native({:int, n}), do: n
  defp ir_value_to_native({:str, s}), do: s
  defp ir_value_to_native({:atom, a}), do: a
end
