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
  alias ExDatalog.Engine.Binding
  alias ExDatalog.IR

  @impl ExDatalog.Constraint
  @doc """
  Evaluates a comparison constraint against a binding environment.

  Accepts an `IR.Constraint` struct as produced by the compiler. Returns
  `{:ok, binding}` (unchanged) when the comparison succeeds, or `:filter`
  when it fails or an input variable is unbound.
  """
  @spec evaluate(IR.Constraint.t(), Binding.t(), Context.t()) ::
          {:ok, Binding.t()} | :filter
  def evaluate(%IR.Constraint{op: op, left: left, right: right}, binding, _context) do
    with {:ok, left_val} <- IR.resolve_operand(left, binding),
         {:ok, right_val} <- IR.resolve_operand(right, binding) do
      if apply_comparison(op, left_val, right_val) do
        {:ok, binding}
      else
        :filter
      end
    else
      :unbound -> :filter
    end
  end

  defp apply_comparison(:gt, left, right), do: left > right
  defp apply_comparison(:lt, left, right), do: left < right
  defp apply_comparison(:gte, left, right), do: left >= right
  defp apply_comparison(:lte, left, right), do: left <= right
  defp apply_comparison(:eq, left, right), do: left == right
  defp apply_comparison(:neq, left, right), do: left != right
end
