defmodule ExDatalog.Constraints.Comparison do
  @moduledoc """
  Comparison constraint implementation for the Constraint behaviour.

  Evaluates comparison constraints (`:gt`, `:lt`, `:gte`, `:lte`, `:eq`,
  `:neq`) which filter bindings without introducing new variable bindings.

  This module is the canonical evaluator for comparison operations. It is
  dispatched to by `ExDatalog.Constraint.evaluate/3` when the constraint's
  `op` is one of the comparison operators.
  """

  @behaviour ExDatalog.Constraint

  alias ExDatalog.Constraint.Context
  alias ExDatalog.IR.Constraint

  @impl ExDatalog.Constraint
  @doc """
  Evaluates a comparison constraint against a binding environment.

  Accepts an `IR.Constraint` struct as produced by the compiler. Returns
  `{:ok, binding}` (unchanged) when the comparison succeeds, or `:filter`
  when it fails or an input variable is unbound.
  """
  @spec evaluate(Constraint.t(), map(), Context.t()) ::
          {:ok, map()} | :filter
  def evaluate(%Constraint{op: op, left: left, right: right}, binding, _context) do
    with {:ok, left_val} <- resolve_operand(left, binding),
         {:ok, right_val} <- resolve_operand(right, binding) do
      if apply_comparison(op, left_val, right_val) do
        {:ok, binding}
      else
        :filter
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
    {:ok, ir_value_to_native(ir_value)}
  end

  defp resolve_operand(:wildcard, _binding), do: :unbound

  defp apply_comparison(:gt, left, right), do: left > right
  defp apply_comparison(:lt, left, right), do: left < right
  defp apply_comparison(:gte, left, right), do: left >= right
  defp apply_comparison(:lte, left, right), do: left <= right
  defp apply_comparison(:eq, left, right), do: left == right
  defp apply_comparison(:neq, left, right), do: left != right

  defp ir_value_to_native({:int, n}), do: n
  defp ir_value_to_native({:str, s}), do: s
  defp ir_value_to_native({:atom, a}), do: a
end
