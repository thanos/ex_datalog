defmodule ExDatalog.Constraints.Aggregate do
  @moduledoc """
  Aggregate constraint evaluation: `count`, `sum`, `min`, `max`.

  Aggregates are **not** evaluated per binding. Unlike comparison or arithmetic
  constraints, an aggregate must see the full set of surviving bindings for a
  rule, group them, and reduce each group to a single value. That grouping is
  performed by `ExDatalog.Engine.Evaluator` via `group_and_reduce/5`; the
  `evaluate/3` callback exists only to satisfy the `ExDatalog.Constraint`
  behaviour and raises if ever invoked through the per-binding pipeline.

  Aggregates are integer-only. `sum` requires integer inputs (validated at
  build time and guarded at runtime). `count` returns the group size. `min`/`max`
  return the smallest/largest input value in the group.
  """

  @behaviour ExDatalog.Constraint

  @dialyzer {:nowarn_function, evaluate: 3}

  @impl ExDatalog.Constraint
  @doc """
  Not supported per-binding. Aggregates are evaluated by the engine's
  group-and-reduce path. Always raises.
  """
  def evaluate(_constraint, _binding, _context) do
    raise "aggregate constraints are not evaluated per-binding; " <>
            "use ExDatalog.Engine.Evaluator group-and-reduce path"
  end

  @doc """
  Groups bindings by `group_vars` and reduces each group's `input_var` values
  with the aggregate `op`, binding the reduced value to `result_var`.

  Returns one extended binding per non-empty group. Empty groups never occur:
  a group exists only because at least one binding produced its key, so the
  reducers (`Enum.min/1`, `Enum.max/1`) are never called on an empty list.

  ## Examples

      iex> bindings = [%{"D" => :eng, "E" => :a}, %{"D" => :eng, "E" => :b}, %{"D" => :ops, "E" => :c}]
      iex> ExDatalog.Constraints.Aggregate.group_and_reduce(bindings, ["D"], :count, "E", "N")
      ...> |> Enum.map(fn b -> {b["D"], b["N"]} end)
      ...> |> Enum.sort()
      [{:eng, 2}, {:ops, 1}]

  """
  @spec group_and_reduce([map()], [String.t()], atom(), String.t(), String.t()) :: [map()]
  def group_and_reduce(bindings, group_vars, op, input_var, result_var) do
    bindings
    |> Enum.group_by(fn binding -> Map.take(binding, group_vars) end)
    |> Enum.map(fn {_key, group} ->
      values = Enum.map(group, fn b -> Map.fetch!(b, input_var) end)
      Map.put(hd(group), result_var, compute(op, values))
    end)
  end

  defp compute(:count, values), do: length(values)
  defp compute(:sum, values), do: reduce_sum(values)
  defp compute(:min, values), do: reduce_min(values)
  defp compute(:max, values), do: reduce_max(values)

  defp reduce_sum(values) do
    Enum.reduce(values, 0, fn
      v, acc when is_integer(v) -> acc + v
      v, _acc -> raise ArgumentError, "sum aggregate requires integer inputs, got: #{inspect(v)}"
    end)
  end

  defp reduce_min([]), do: raise(ArgumentError, "min aggregate called on empty group")

  defp reduce_min(values) do
    Enum.reduce(values, nil, fn
      v, nil when is_integer(v) -> v
      v, acc when is_integer(v) -> min(v, acc)
      v, _acc -> raise(ArgumentError, "min aggregate requires integer inputs, got: #{inspect(v)}")
    end)
  end

  defp reduce_max([]), do: raise(ArgumentError, "max aggregate called on empty group")

  defp reduce_max(values) do
    Enum.reduce(values, nil, fn
      v, nil when is_integer(v) -> v
      v, acc when is_integer(v) -> max(v, acc)
      v, _acc -> raise(ArgumentError, "max aggregate requires integer inputs, got: #{inspect(v)}")
    end)
  end
end
