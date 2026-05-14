defmodule ExDatalog.Constraints.Type do
  @moduledoc """
  Type predicate constraint implementation for the Constraint behaviour.

  Evaluates type-check constraints (`:is_integer`, `:is_binary`, `:is_atom`)
  which filter bindings based on the Elixir type of a bound value. These are
  unary constraints: only `left` is evaluated, `right` and `result` are `nil`.
  """

  @behaviour ExDatalog.Constraint

  alias ExDatalog.Constraint.Context
  alias ExDatalog.IR.Constraint

  @impl ExDatalog.Constraint
  @doc """
  Evaluates a type predicate constraint against a binding environment.

  Accepts an `IR.Constraint` struct as produced by the compiler. Returns
  `{:ok, binding}` (unchanged) when the type check passes, or `:filter`
  when it fails or the input variable is unbound.
  """
  @spec evaluate(Constraint.t(), map(), Context.t()) ::
          {:ok, map()} | :filter
  def evaluate(%Constraint{op: op, left: left}, binding, _context) do
    case resolve_operand(left, binding) do
      {:ok, value} ->
        if type_check(op, value), do: {:ok, binding}, else: :filter

      :unbound ->
        :filter
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

  defp type_check(:is_integer, v), do: is_integer(v)
  defp type_check(:is_binary, v), do: is_binary(v)
  defp type_check(:is_atom, v), do: is_atom(v)

  defp ir_value_to_native({:int, n}), do: n
  defp ir_value_to_native({:str, s}), do: s
  defp ir_value_to_native({:atom, a}), do: a
end
