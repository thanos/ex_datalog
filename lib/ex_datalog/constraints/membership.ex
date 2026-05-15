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
  alias ExDatalog.Engine.Binding
  alias ExDatalog.IR

  @impl ExDatalog.Constraint
  @doc """
  Evaluates a membership constraint against a binding environment.

  Accepts an `IR.Constraint` struct as produced by the compiler. Returns
  `{:ok, binding}` (unchanged) when the left value is a member of the
  right list, or `:filter` when it is not or the left variable is unbound.
  """
  @spec evaluate(IR.Constraint.t(), Binding.t(), Context.t()) ::
          {:ok, Binding.t()} | :filter
  def evaluate(%IR.Constraint{left: left, right: right}, binding, _context) do
    with {:ok, value} <- IR.resolve_operand(left, binding),
         {:ok, list} <- resolve_list(right) do
      if value in list do
        {:ok, binding}
      else
        :filter
      end
    else
      _ -> :filter
    end
  end

  defp resolve_list({:const, {:list, elements}}) do
    {:ok, Enum.map(elements, &IR.value_to_native/1)}
  end

  defp resolve_list(_), do: :invalid_list
end
