defmodule ExDatalog.Constraints.String do
  @moduledoc """
  String predicate constraint implementation for the Constraint behaviour.

  Evaluates string constraints (`:starts_with`, `:contains`) which filter
  bindings based on string relationships. Both operands must be bound and
  resolve to binaries (strings). Returns `:filter` if either operand is
  unbound or not a binary.
  """

  @behaviour ExDatalog.Constraint

  alias ExDatalog.Constraint.Context
  alias ExDatalog.IR.Constraint

  @impl ExDatalog.Constraint
  @doc """
  Evaluates a string predicate constraint against a binding environment.

  Accepts an `IR.Constraint` struct as produced by the compiler. Returns
  `{:ok, binding}` (unchanged) when the predicate passes, or `:filter`
  when it fails or an input variable is unbound or not a binary.
  """
  @spec evaluate(Constraint.t(), map(), Context.t()) ::
          {:ok, map()} | :filter
  def evaluate(%Constraint{op: op, left: left, right: right}, binding, _context) do
    with {:ok, left_val} <- resolve_operand(left, binding),
         {:ok, right_val} <- resolve_operand(right, binding),
         true <- is_binary(left_val),
         true <- is_binary(right_val) do
      if apply_predicate(op, left_val, right_val) do
        {:ok, binding}
      else
        :filter
      end
    else
      :unbound -> :filter
      false -> :filter
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

  defp apply_predicate(:starts_with, left, right), do: String.starts_with?(left, right)
  defp apply_predicate(:contains, left, right), do: String.contains?(left, right)

  defp ir_value_to_native({:int, n}), do: n
  defp ir_value_to_native({:str, s}), do: s
  defp ir_value_to_native({:atom, a}), do: a
end
