defmodule ExDatalog.Constraints.Membership do
  @moduledoc """
  Membership constraint implementation for the Constraint behaviour.

  Evaluates membership constraints (`:member`) which filter bindings based
  on whether a value is present in a constant list. The `left` operand must
  be bound; the `right` operand must be a constant list. Returns `:filter`
  when the value is not in the list or the left variable is unbound.
  """

  @behaviour ExDatalog.Constraint

  alias ExDatalog.Constraint.Context
  alias ExDatalog.IR.Constraint

  @impl ExDatalog.Constraint
  @doc """
  Evaluates a membership constraint against a binding environment.

  Accepts an `IR.Constraint` struct as produced by the compiler. Returns
  `{:ok, binding}` (unchanged) when the left value is a member of the
  right list, or `:filter` when it is not or the left variable is unbound.
  """
  @spec evaluate(Constraint.t(), map(), Context.t()) ::
          {:ok, map()} | :filter
  def evaluate(%Constraint{left: left, right: right}, binding, _context) do
    with {:ok, value} <- resolve_operand(left, binding),
         {:ok, list} <- resolve_list(right) do
      if value in list do
        {:ok, binding}
      else
        :filter
      end
    else
      :unbound -> :filter
      :invalid_list -> :filter
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

  defp resolve_list({:const, list}) when is_list(list), do: {:ok, list}

  defp resolve_list(_), do: :invalid_list

  defp ir_value_to_native({:int, n}), do: n
  defp ir_value_to_native({:str, s}), do: s
  defp ir_value_to_native({:atom, a}), do: a
end
