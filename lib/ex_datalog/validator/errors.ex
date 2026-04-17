defmodule ExDatalog.Validator.Errors do
  @moduledoc """
  Structured validation error types for ExDatalog programs.

  Every error is a `%ExDatalog.Validator.Errors{}` struct with:

  - `kind` — a machine-readable atom identifying the error category.
  - `context` — a map with error-specific context (relation, variable, rule index, etc.).
  - `message` — a human-readable description.

  ## Error Kinds

  | Kind | Phase | Description |
  |---|---|---|
  | `:arity_mismatch` | 1 | Fact or atom term count differs from relation arity |
  | `:undefined_relation` | 1 | Reference to a relation not declared in the program |
  | `:invalid_term` | 1 | A term is not a valid `ExDatalog.Term.t()` |
  | `:duplicate_relation` | 1 | A relation is declared more than once |
  | `:unsafe_variable` | 2 | A head variable does not appear in any positive body atom |
  | `:range_restriction` | 2 | A variable in a constraint is not bound by positive body atoms |
  | `:unstratified_negation` | 2 | A negative edge appears in a dependency cycle |
  | `:unbound_constraint_variable` | 2 | A constraint references a variable not yet bound |
  | `:invalid_body_literal` | 1 | A body literal is not `{:positive, atom}` or `{:negative, atom}` |

  ## Examples

      iex> ExDatalog.Validator.Errors.new(:undefined_relation, %{relation: "parent", rule_index: 0}, "rule 0 references undefined relation \\"parent\\"")
      %ExDatalog.Validator.Errors{
        kind: :undefined_relation,
        context: %{relation: "parent", rule_index: 0},
        message: "rule 0 references undefined relation \\"parent\\""
      }

  """

  @type kind ::
          :arity_mismatch
          | :undefined_relation
          | :invalid_term
          | :duplicate_relation
          | :unsafe_variable
          | :range_restriction
          | :unstratified_negation
          | :unbound_constraint_variable
          | :invalid_body_literal
          | :wildcard_in_head

  @type t :: %__MODULE__{
          kind: kind(),
          context: map(),
          message: String.t()
        }

  defstruct [:kind, :context, :message]

  @doc """
  Constructs a new validation error.

  ## Examples

      iex> ExDatalog.Validator.Errors.new(:arity_mismatch, %{relation: "parent", expected: 2, got: 1}, "arity mismatch")
      %ExDatalog.Validator.Errors{
        kind: :arity_mismatch,
        context: %{relation: "parent", expected: 2, got: 1},
        message: "arity mismatch"
      }

  """
  @spec new(kind(), map(), String.t()) :: t()
  def new(kind, context, message)
      when is_atom(kind) and is_map(context) and is_binary(message) do
    %__MODULE__{kind: kind, context: context, message: message}
  end
end
