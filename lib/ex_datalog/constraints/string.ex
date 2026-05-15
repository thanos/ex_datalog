defmodule ExDatalog.Constraints.StringPredicate do
  @moduledoc """
  String predicate constraint implementation for the Constraint behaviour.

  Evaluates string constraints (`:starts_with`, `:contains`) which filter
  bindings based on string relationships. Both operands must be bound and
  resolve to binaries (strings). Returns `:filter` if either operand is
  unbound or not a binary.
  """

  @behaviour ExDatalog.Constraint

  alias ExDatalog.Constraint.Context
  alias ExDatalog.Engine.Binding
  alias ExDatalog.IR

  @impl ExDatalog.Constraint
  @doc """
  Evaluates a string predicate constraint against a binding environment.

  Accepts an `IR.Constraint` struct as produced by the compiler. Returns
  `{:ok, binding}` (unchanged) when the predicate passes, or `:filter`
  when it fails or an input variable is unbound or not a binary.
  """
  @spec evaluate(IR.Constraint.t(), Binding.t(), Context.t()) ::
          {:ok, Binding.t()} | :filter
  def evaluate(%IR.Constraint{op: op, left: left, right: right}, binding, _context) do
    with {:ok, left_val} <- IR.resolve_operand(left, binding),
         {:ok, right_val} <- IR.resolve_operand(right, binding),
         true <- is_binary(left_val),
         true <- is_binary(right_val) do
      if apply_predicate(op, left_val, right_val) do
        {:ok, binding}
      else
        :filter
      end
    else
      _ -> :filter
    end
  end

  defp apply_predicate(:starts_with, left, right), do: String.starts_with?(left, right)
  defp apply_predicate(:contains, left, right), do: String.contains?(left, right)
end
