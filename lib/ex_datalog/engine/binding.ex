defmodule ExDatalog.Engine.Binding do
  @moduledoc """
  Binding environment for Datalog rule evaluation.

  A binding maps variable names (strings) to ground values. During rule
  evaluation, each body atom extends the binding by matching tuple values
  against atom terms. Constraints filter or extend bindings further.

  ## Types of resolution

  - **Variable** (`{:var, "X"}`) — looked up in the binding. If absent, the
    variable is unbound and the constraint/atom cannot be evaluated.
  - **Constant** (`{:const, {:int, 42}}`, `{:const, {:atom, :alice}}`, etc.) —
    resolved to the native Elixir value.
  - **Wildcard** (`:wildcard`) — matches any value without binding.

  ## Merge semantics

  When joining two atoms that share variables, two bindings are merged. For
  shared variables the values must agree; otherwise the merge fails and the
  candidate tuple is discarded.
  """

  alias ExDatalog.IR

  @type t :: %{String.t() => term()}

  @doc """
  Creates an empty binding environment.

  ## Examples

      iex> ExDatalog.Engine.Binding.empty()
      %{}

  """
  @spec empty() :: t()
  def empty, do: %{}

  @doc """
  Binds a variable to a value in the environment.

  ## Examples

      iex> ExDatalog.Engine.Binding.bind(%{}, "X", :alice)
      %{"X" => :alice}

      iex> ExDatalog.Engine.Binding.bind(%{"X" => :alice}, "Y", :bob)
      %{"X" => :alice, "Y" => :bob}

  """
  @spec bind(t(), String.t(), term()) :: t()
  def bind(binding, var_name, value), do: Map.put(binding, var_name, value)

  @doc """
  Looks up a variable in the binding environment.

  Returns `{:ok, value}` if bound, `:error` if not.

  ## Examples

      iex> ExDatalog.Engine.Binding.get(%{"X" => :alice}, "X")
      {:ok, :alice}

      iex> ExDatalog.Engine.Binding.get(%{"X" => :alice}, "Y")
      :error

  """
  @spec get(t(), String.t()) :: {:ok, term()} | :error
  def get(binding, var_name), do: Map.fetch(binding, var_name)

  @doc """
  Resolves an IR term to a native Elixir value using a binding environment.

  - `{:var, name}` — looks up in binding. Returns `{:ok, value}` if bound,
    `:unbound` if not.
  - `{:const, ir_value}` — returns `{:ok, native_value}` unconditionally.
  - `:wildcard` — returns `:wildcard` (matches anything, cannot be resolved).

  ## Examples

      iex> ExDatalog.Engine.Binding.resolve(%{"X" => 42}, {:var, "X"})
      {:ok, 42}

      iex> ExDatalog.Engine.Binding.resolve(%{}, {:var, "X"})
      :unbound

      iex> ExDatalog.Engine.Binding.resolve(%{}, {:const, {:int, 10}})
      {:ok, 10}

      iex> ExDatalog.Engine.Binding.resolve(%{}, {:const, {:atom, :alice}})
      {:ok, :alice}

      iex> ExDatalog.Engine.Binding.resolve(%{}, :wildcard)
      :wildcard

  """
  @spec resolve(t(), IR.ir_term()) :: {:ok, term()} | :unbound | :wildcard
  def resolve(binding, {:var, name}) do
    case Map.fetch(binding, name) do
      {:ok, value} -> {:ok, value}
      :error -> :unbound
    end
  end

  def resolve(_binding, {:const, value}), do: {:ok, ir_value_to_native(value)}

  def resolve(_binding, :wildcard), do: :wildcard

  @doc """
  Merges two binding environments.

  For shared variables, the values must be equal (using `==/2`). If any
  shared variable disagrees, returns `:conflict`. Otherwise returns
  `{:ok, merged_binding}`.

  ## Examples

      iex> ExDatalog.Engine.Binding.merge(%{"X" => 1}, %{"Y" => 2})
      {:ok, %{"X" => 1, "Y" => 2}}

      iex> ExDatalog.Engine.Binding.merge(%{"X" => 1}, %{"X" => 1, "Y" => 2})
      {:ok, %{"X" => 1, "Y" => 2}}

      iex> ExDatalog.Engine.Binding.merge(%{"X" => 1}, %{"X" => 2})
      :conflict

  """
  @spec merge(t(), t()) :: {:ok, t()} | :conflict
  def merge(b1, b2) do
    Enum.reduce_while(b2, {:ok, b1}, fn {k, v2}, {:ok, acc} ->
      case Map.fetch(acc, k) do
        {:ok, v1} when v1 == v2 -> {:cont, {:ok, acc}}
        {:ok, _v1} -> {:halt, :conflict}
        :error -> {:cont, {:ok, Map.put(acc, k, v2)}}
      end
    end)
  end

  @doc """
  Checks whether two binding environments are consistent on shared variables.

  Returns `true` if every variable present in both bindings has the same value,
  `false` otherwise.

  ## Examples

      iex> ExDatalog.Engine.Binding.consistent?(%{"X" => 1}, %{"X" => 1, "Y" => 2})
      true

      iex> ExDatalog.Engine.Binding.consistent?(%{"X" => 1}, %{"X" => 2})
      false

      iex> ExDatalog.Engine.Binding.consistent?(%{"X" => 1}, %{"Y" => 2})
      true

  """
  @spec consistent?(t(), t()) :: boolean()
  def consistent?(b1, b2) do
    smaller = if map_size(b1) <= map_size(b2), do: b1, else: b2
    larger = if map_size(b1) <= map_size(b2), do: b2, else: b1

    Enum.all?(smaller, fn {k, v} ->
      case Map.fetch(larger, k) do
        {:ok, v2} -> v == v2
        :error -> true
      end
    end)
  end

  @doc """
  Converts an IR value tag to its native Elixir value.

  Used internally by `resolve/2` and by the evaluator for fact conversion.

  ## Examples

      iex> ExDatalog.Engine.Binding.ir_value_to_native({:int, 42})
      42

      iex> ExDatalog.Engine.Binding.ir_value_to_native({:str, "hello"})
      "hello"

      iex> ExDatalog.Engine.Binding.ir_value_to_native({:atom, :alice})
      :alice

  """
  @spec ir_value_to_native(IR.ir_value()) :: term()
  def ir_value_to_native({:int, n}), do: n
  def ir_value_to_native({:str, s}), do: s
  def ir_value_to_native({:atom, a}), do: a
end
