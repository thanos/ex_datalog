defmodule ExDatalog.Callback do
  @moduledoc """
  A BEAM callback predicate: an Elixir function invoked during rule evaluation.

  Callbacks let rule bodies call deterministic, side-effect-free Elixir
  functions as predicates. A callback appears in a rule body as
  `{:callback, %ExDatalog.Callback{}}`, alongside positive/negative atoms.

  ## Fields

  - `module` — the module exporting the function.
  - `function` — the function name (atom).
  - `args` — a list of `ExDatalog.Term.t()` (variables/constants) resolved
    against the binding and passed positionally to the function.
  - `result` — `nil` for boolean (filter) callbacks; `{:var, name}` for
    value-returning callbacks that bind the function's return value.

  ## Safety contract

  A callback **must** be:

  - **Deterministic** — the same arguments always produce the same result.
  - **Side-effect free** — no I/O, mutation, or messaging.

  The engine enforces only timeout and exception isolation: a callback that
  exceeds `callback_timeout_ms` (default 100ms) or raises is treated as a
  filtered binding (the fact is not derived). Determinism and purity are
  caller contracts, not enforced by the engine.

  ## Examples

      iex> alias ExDatalog.{Callback, Term}
      iex> Callback.new(String, :starts_with?, [Term.var("S"), Term.const("a")])
      %ExDatalog.Callback{module: String, function: :starts_with?, args: [{:var, "S"}, {:const, "a"}], result: nil}

  """

  alias ExDatalog.Term

  @enforce_keys [:module, :function, :args]
  defstruct [:module, :function, :args, :result]

  @type t :: %__MODULE__{
          module: module(),
          function: atom(),
          args: [Term.t()],
          result: Term.t() | nil
        }

  @doc """
  Constructs a callback predicate.

  `result` defaults to `nil` (a boolean filter callback). Pass a
  `{:var, name}` term to bind the function's return value.

  ## Examples

      iex> alias ExDatalog.{Callback, Term}
      iex> Callback.new(MyMod, :adult?, [Term.var("Age")])
      %ExDatalog.Callback{module: MyMod, function: :adult?, args: [{:var, "Age"}], result: nil}

      iex> alias ExDatalog.{Callback, Term}
      iex> Callback.new(MyMod, :score, [Term.var("X")], Term.var("S"))
      %ExDatalog.Callback{module: MyMod, function: :score, args: [{:var, "X"}], result: {:var, "S"}}

  """
  @spec new(module(), atom(), [Term.t()], Term.t() | nil) :: t()
  def new(module, function, args, result \\ nil)
      when is_atom(module) and is_atom(function) and is_list(args) do
    %__MODULE__{module: module, function: function, args: args, result: result}
  end

  @doc """
  Returns the input variable names referenced by the callback's arguments.

  These must be bound by positive body atoms before the callback runs.

  ## Examples

      iex> alias ExDatalog.{Callback, Term}
      iex> cb = Callback.new(MyMod, :ok?, [Term.var("A"), Term.const(1), Term.var("B")])
      iex> ExDatalog.Callback.input_variables(cb)
      ["A", "B"]

  """
  @spec input_variables(t()) :: [String.t()]
  def input_variables(%__MODULE__{args: args}), do: Term.variables(args)

  @doc """
  Returns the result variable name for a value-returning callback, or `nil`.

  ## Examples

      iex> alias ExDatalog.{Callback, Term}
      iex> ExDatalog.Callback.result_variable(Callback.new(M, :f, [Term.var("X")], Term.var("R")))
      "R"

      iex> alias ExDatalog.{Callback, Term}
      iex> ExDatalog.Callback.result_variable(Callback.new(M, :f, [Term.var("X")]))
      nil

  """
  @spec result_variable(t()) :: String.t() | nil
  def result_variable(%__MODULE__{result: {:var, name}}), do: name
  def result_variable(%__MODULE__{result: _}), do: nil
end
