defmodule ExDatalog.Constraints.Type do
  @moduledoc """
  Type predicate constraint implementation for the Constraint behaviour.

  Evaluates type-check constraints (`:is_integer`, `:is_binary`, `:is_atom`)
  which filter bindings based on the Elixir type of a bound value. These are
  unary constraints: only `left` is evaluated, `right` and `result` are `nil`.
  """

  @behaviour ExDatalog.Constraint

  alias ExDatalog.Constraint.Context
  alias ExDatalog.IR

  @impl ExDatalog.Constraint
  @doc """
  Evaluates a type predicate constraint against a binding environment.

  Accepts an `IR.Constraint` struct as produced by the compiler. Returns
  `{:ok, binding}` (unchanged) when the type check passes, or `:filter`
  when it fails or the input variable is unbound.
  """
  @spec evaluate(IR.Constraint.t(), map(), Context.t()) ::
          {:ok, map()} | :filter
  def evaluate(%IR.Constraint{op: op, left: left}, binding, _context) do
    case IR.resolve_operand(left, binding) do
      {:ok, value} ->
        if type_check(op, value), do: {:ok, binding}, else: :filter

      :unbound ->
        :filter
    end
  end

  defp type_check(:is_integer, v), do: is_integer(v)
  defp type_check(:is_binary, v), do: is_binary(v)
  defp type_check(:is_atom, v), do: is_atom(v)
end
