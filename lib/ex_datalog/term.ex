defmodule ExDatalog.Term do
  @moduledoc """
  Term types used in Datalog atom arguments.

  A term is one of:

  - A logic variable: `{:var, name}` — matches any value and binds it to `name`.
  - A constant: `{:const, value}` — a ground value (integer, string, or atom).
  - A wildcard: `:wildcard` — an anonymous variable that matches any value without binding.

  ## Examples

      iex> ExDatalog.Term.var("X")
      {:var, "X"}

      iex> ExDatalog.Term.const(:alice)
      {:const, :alice}

      iex> ExDatalog.Term.const(42)
      {:const, 42}

      iex> ExDatalog.Term.wildcard()
      :wildcard

  """

  @type var_name :: String.t()
  @type value :: integer() | String.t() | atom()
  @type t :: {:var, var_name()} | {:const, value()} | :wildcard

  @doc """
  Constructs a logic variable term.

  ## Examples

      iex> ExDatalog.Term.var("X")
      {:var, "X"}

      iex> ExDatalog.Term.var("ParentNode")
      {:var, "ParentNode"}

  """
  @spec var(var_name()) :: {:var, var_name()}
  def var(name) when is_binary(name) and byte_size(name) > 0, do: {:var, name}

  @doc """
  Constructs a constant term.

  Accepts integers, strings, and atoms. Floats are not supported — Datalog
  relations use discrete values. If you pass a float, `const/1` raises
  `ArgumentError`.

  Note that `true`, `false`, and `nil` are valid Elixir atoms and are
  accepted as constants, producing `{:const, true}`, `{:const, false}`,
  and `{:const, nil}` respectively. Use these with care — `nil` in
  particular may be confused with an absent value downstream.

  ## Examples

      iex> ExDatalog.Term.const(:alice)
      {:const, :alice}

      iex> ExDatalog.Term.const(42)
      {:const, 42}

      iex> ExDatalog.Term.const("hello")
      {:const, "hello"}

  """
  @spec const(value()) :: {:const, value()}
  def const(value) when is_integer(value) or is_binary(value) or is_atom(value),
    do: {:const, value}

  def const(value) when is_float(value),
    do: raise(ArgumentError, "float values are not supported: #{inspect(value)}")

  def const(value),
    do: raise(ArgumentError, "unsupported constant value: #{inspect(value)}")

  @doc """
  Constructs an anonymous wildcard term.

  A wildcard matches any value but does not bind it to a name.
  Wildcards may appear in rule bodies but not in rule heads.

  ## Examples

      iex> ExDatalog.Term.wildcard()
      :wildcard

  """
  @spec wildcard() :: :wildcard
  def wildcard, do: :wildcard

  @doc """
  Returns `true` if the term is a logic variable.

  ## Examples

      iex> ExDatalog.Term.var?({:var, "X"})
      true

      iex> ExDatalog.Term.var?({:const, :alice})
      false

      iex> ExDatalog.Term.var?(:wildcard)
      false

  """
  @spec var?(t()) :: boolean()
  def var?({:var, _}), do: true
  def var?(_), do: false

  @doc """
  Returns `true` if the term is a constant.

  ## Examples

      iex> ExDatalog.Term.const?({:const, :alice})
      true

      iex> ExDatalog.Term.const?({:var, "X"})
      false

      iex> ExDatalog.Term.const?(:wildcard)
      false

  """
  @spec const?(t()) :: boolean()
  def const?({:const, _}), do: true
  def const?(_), do: false

  @doc """
  Returns `true` if the term is a wildcard.

  ## Examples

      iex> ExDatalog.Term.wildcard?(:wildcard)
      true

      iex> ExDatalog.Term.wildcard?({:var, "X"})
      false

  """
  @spec wildcard?(t()) :: boolean()
  def wildcard?(:wildcard), do: true
  def wildcard?(_), do: false

  @doc """
  Returns `true` if the term is a valid `ExDatalog.Term.t()`.

  ## Examples

      iex> ExDatalog.Term.valid?({:var, "X"})
      true

      iex> ExDatalog.Term.valid?({:const, 42})
      true

      iex> ExDatalog.Term.valid?(:wildcard)
      true

      iex> ExDatalog.Term.valid?(:bad)
      false

  """
  @spec valid?(term()) :: boolean()
  def valid?({:var, name}) when is_binary(name) and byte_size(name) > 0, do: true
  def valid?({:const, v}) when is_integer(v) or is_binary(v) or is_atom(v), do: true
  def valid?(:wildcard), do: true
  def valid?(_), do: false

  @doc """
  Returns all variable names present in a list of terms.

  ## Examples

      iex> ExDatalog.Term.variables([{:var, "X"}, {:const, :alice}, {:var, "Y"}, :wildcard])
      ["X", "Y"]

  """
  @spec variables([t()]) :: [var_name()]
  def variables(terms) when is_list(terms) do
    for {:var, name} <- terms, do: name
  end
end
