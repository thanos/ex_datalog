defmodule ExDatalog.Capabilities do
  @moduledoc """
  Capability metadata for storage backends and constraint sets.

  Capabilities enable engines and tooling to reason about what a given
  configuration supports — portable constraints, indexed lookup, provenance,
  etc. — without runtime introspection of implementation details.

  ## Fields

  | Field | Default | Description |
  |---|---|---|
  | `storage_type` | `:map` | Storage backend type (`:map`, `:ets`, `:external`) |
  | `indexed_lookup` | `false` | Supports indexed (hash) lookups |
  | `concurrent_reads` | `false` | Safe for concurrent read access |
  | `arithmetic_constraints` | `true` | Supports arithmetic constraints |
  | `comparison_constraints` | `true` | Supports comparison constraints |
  | `type_predicates` | `true` | Supports type-check predicates |
  | `string_predicates` | `true` | Supports string predicates |
  | `provenance` | `true` | Supports derivation provenance |
  | `external_execution` | `false` | Reserved for Z3, Soufflé, etc. |

  ## Usage

      iex> ExDatalog.Capabilities.default()
      %ExDatalog.Capabilities{
        storage_type: :map,
        indexed_lookup: false,
        concurrent_reads: false,
        arithmetic_constraints: true,
        comparison_constraints: true,
        type_predicates: false,
        string_predicates: false,
        provenance: true,
        external_execution: false
      }

  """

  @type storage_type :: :map | :ets | :external

  @type t :: %__MODULE__{
          storage_type: storage_type(),
          indexed_lookup: boolean(),
          concurrent_reads: boolean(),
          arithmetic_constraints: boolean(),
          comparison_constraints: boolean(),
          type_predicates: boolean(),
          string_predicates: boolean(),
          provenance: boolean(),
          external_execution: boolean()
        }

  defstruct storage_type: :map,
            indexed_lookup: false,
            concurrent_reads: false,
            arithmetic_constraints: true,
            comparison_constraints: true,
            type_predicates: true,
            string_predicates: true,
            provenance: true,
            external_execution: false

  @doc """
  Returns the default capabilities struct.

  Represents the baseline capability set for the Map backend:
  arithmetic, comparison, type-check, and string predicates, provenance, but no indexed
  lookup, concurrent reads, or external execution.

  ## Examples

      iex> cap = ExDatalog.Capabilities.default()
      iex> cap.arithmetic_constraints
      true
      iex> cap.indexed_lookup
      false

  """
  def default, do: %__MODULE__{}
end
