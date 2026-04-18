defmodule ExDatalog.Engine.Join do
  @moduledoc """
  Stateless join primitives for semi-naive Datalog evaluation.

  This module provides the core matching and joining functions used by the
  `Engine.Evaluator` during rule evaluation:

  - `match_tuple/3` — matches a single storage tuple against an atom's IR
    terms, extending the binding if variables are unbound or verifying them if
    already bound.
  - `join/3` — joins a list of binding environments with a collection of
    tuples for a single body atom. This is the sequential-scan version used
    by `Engine.Naive` in v0.1.0.
  - `project/2` — projects a binding environment onto a head atom's variables,
    producing a result tuple.

  The indexed variant `join_indexed/4` is implemented but **not used** by the
  default engine. It is exposed for alternative engine implementations and
  will be wired into the evaluator in a future release.

  All functions are pure and stateless; storage and index management is handled
  by `ExDatalog.Storage` and `Engine.Naive` respectively.
  """

  alias ExDatalog.Engine.Binding
  alias ExDatalog.IR

  @type binding :: Binding.t()
  @type ir_term :: IR.ir_term()

  @doc """
  Matches a storage tuple against a list of IR terms, extending the binding.

  For each position `i` in the terms list:

  - `{:var, name}` — if `name` is bound, the tuple value at position `i` must
    equal the bound value. If unbound, `name` is bound to the tuple value.
  - `{:const, ir_value}` — the tuple value at position `i` must equal the
    native value of `ir_value`.
  - `:wildcard` — any value matches; no binding change.

  Returns `{:ok, extended_binding}` if all positions match, or `:no_match`.
  The terms list and the tuple must have the same length.

  ## Examples

      iex> alias ExDatalog.Engine.Join
      iex> terms = [{:var, "X"}, {:var, "Y"}]
      iex> Join.match_tuple(terms, {:alice, :bob}, %{})
      {:ok, %{"X" => :alice, "Y" => :bob}}

      iex> terms = [{:var, "X"}, {:const, {:atom, :bob}}]
      iex> Join.match_tuple(terms, {:alice, :bob}, %{})
      {:ok, %{"X" => :alice}}

      iex> terms = [{:var, "X"}, {:const, {:atom, :carol}}]
      iex> Join.match_tuple(terms, {:alice, :bob}, %{})
      :no_match

      iex> terms = [{:var, "X"}, {:var, "X"}]
      iex> Join.match_tuple(terms, {:alice, :alice}, %{})
      {:ok, %{"X" => :alice}}

      iex> terms = [{:var, "X"}, {:var, "X"}]
      iex> Join.match_tuple(terms, {:alice, :bob}, %{})
      :no_match

  """
  @spec match_tuple([ir_term()], tuple(), binding()) :: {:ok, binding()} | :no_match
  def match_tuple(terms, tuple, binding) when is_list(terms) and is_tuple(tuple) do
    if length(terms) != tuple_size(tuple) do
      :no_match
    else
      match_at(terms, tuple, 0, binding)
    end
  end

  defp match_at([], _tuple, _idx, binding), do: {:ok, binding}

  defp match_at([{:var, name} | rest], tuple, idx, binding) do
    value = elem(tuple, idx)

    case Map.fetch(binding, name) do
      {:ok, existing} when existing == value ->
        match_at(rest, tuple, idx + 1, binding)

      {:ok, _different} ->
        :no_match

      :error ->
        match_at(rest, tuple, idx + 1, Map.put(binding, name, value))
    end
  end

  defp match_at([{:const, ir_value} | rest], tuple, idx, binding) do
    value = elem(tuple, idx)
    expected = Binding.ir_value_to_native(ir_value)

    if value == expected do
      match_at(rest, tuple, idx + 1, binding)
    else
      :no_match
    end
  end

  defp match_at([:wildcard | rest], tuple, idx, binding) do
    match_at(rest, tuple, idx + 1, binding)
  end

  defp match_at(_, _, _, _), do: :no_match

  @doc """
  Joins a list of binding environments with a collection of tuples using a
  sequential scan.

  For each `(binding, tuple)` pair, calls `match_tuple/3`. Collects all
  successful matches. This is O(bindings × tuples) and suitable for small
  relations or when no index is available.

  ## Examples

      iex> alias ExDatalog.Engine.Join
      iex> terms = [{:var, "X"}, {:var, "Y"}]
      iex> tuples = [{:alice, :bob}, {:carol, :dave}]
      iex> Join.join([%{}], terms, tuples)
      [%{"X" => :alice, "Y" => :bob}, %{"X" => :carol, "Y" => :dave}]

      iex> terms = [{:var, "X"}, {:var, "Y"}]
      iex> tuples = [{:alice, :bob}, {:carol, :dave}]
      iex> Join.join([%{"X" => :alice}], terms, tuples)
      [%{"X" => :alice, "Y" => :bob}]

  """
  @spec join([binding()], [ir_term()], [tuple()]) :: [binding()]
  def join(bindings, terms, tuples) do
    for binding <- bindings,
        tuple <- tuples,
        {:ok, extended} <- [match_tuple(terms, tuple, binding)] do
      extended
    end
  end

  @doc false
  @spec join_indexed([binding()], [ir_term()], %{tuple() => [tuple()]}, [non_neg_integer()]) ::
          [binding()]
  def join_indexed(bindings, terms, index, join_columns) do
    for binding <- bindings,
        key = compute_key(binding, terms, join_columns),
        {:ok, matches} <- [Map.fetch(index, key)],
        tuple <- matches,
        {:ok, extended} <- [match_tuple(terms, tuple, binding)] do
      extended
    end
  end

  @doc """
  Projects a binding environment onto a head atom's IR terms, producing a
  result tuple.

  For each term in the head atom:

  - `{:var, name}` — look up `name` in the binding and use its value.
  - `{:const, ir_value}` — use the native value of `ir_value`.
  - `:wildcard` — not valid in rule heads (caught by the validator).

  Returns an Elixir tuple suitable for insertion into a storage relation.

  ## Examples

      iex> alias ExDatalog.Engine.Join
      iex> ir_atom = %ExDatalog.IR.Atom{relation: "ancestor", terms: [{:var, "X"}, {:var, "Y"}]}
      iex> Join.project(ir_atom, %{"X" => :alice, "Y" => :bob})
      {:alice, :bob}

      iex> ir_atom = %ExDatalog.IR.Atom{relation: "result", terms: [{:var, "X"}, {:const, {:atom, :ok}}]}
      iex> Join.project(ir_atom, %{"X" => 42})
      {42, :ok}

  """
  @spec project(IR.Atom.t(), binding()) :: tuple()
  def project(%IR.Atom{terms: terms}, binding) do
    values =
      Enum.map(terms, fn
        {:var, name} -> Map.fetch!(binding, name)
        {:const, ir_value} -> Binding.ir_value_to_native(ir_value)
      end)

    List.to_tuple(values)
  end

  defp compute_key(binding, terms, join_columns) do
    values =
      Enum.map(join_columns, fn col ->
        case Enum.at(terms, col) do
          {:var, name} -> Map.fetch!(binding, name)
          {:const, ir_value} -> Binding.ir_value_to_native(ir_value)
        end
      end)

    List.to_tuple(values)
  end
end
