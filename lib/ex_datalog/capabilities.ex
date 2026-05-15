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

  ## Merging

  `merge/2` combines two capability structs using AND semantics: a field
  is `true` only if both inputs are `true`. The `storage_type` field takes
  the left operand's value.

      iex> cap1 = %ExDatalog.Capabilities{indexed_lookup: true, concurrent_reads: false}
      iex> cap2 = %ExDatalog.Capabilities{indexed_lookup: false, concurrent_reads: true}
      iex> merged = ExDatalog.Capabilities.merge(cap1, cap2)
      iex> merged.indexed_lookup
      false
      iex> merged.concurrent_reads
      false
      iex> merged.arithmetic_constraints
      true

  ## Satisfying requirements

  `satisfies?/2` checks whether a capability struct meets a set of
  requirements. A requirement is a keyword list of boolean fields that must
  all be `true` in the capability struct.

      iex> caps = %ExDatalog.Capabilities{arithmetic_constraints: true, indexed_lookup: true}
      iex> ExDatalog.Capabilities.satisfies?(caps, arithmetic_constraints: true, indexed_lookup: true)
      true
      iex> ExDatalog.Capabilities.satisfies?(caps, arithmetic_constraints: true, concurrent_reads: true)
      false

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

  @boolean_fields [
    :indexed_lookup,
    :concurrent_reads,
    :arithmetic_constraints,
    :comparison_constraints,
    :type_predicates,
    :string_predicates,
    :provenance,
    :external_execution
  ]

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

  @doc """
  Merges two capability structs using AND semantics.

  For each boolean field, the result is `true` only if both inputs are `true`.
  The `storage_type` field takes the left operand's value.

  ## Examples

      iex> cap1 = %ExDatalog.Capabilities{indexed_lookup: true, concurrent_reads: false}
      iex> cap2 = %ExDatalog.Capabilities{indexed_lookup: false, concurrent_reads: true}
      iex> merged = ExDatalog.Capabilities.merge(cap1, cap2)
      iex> merged.indexed_lookup
      false
      iex> merged.concurrent_reads
      false
      iex> merged.arithmetic_constraints
      true

  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = left, %__MODULE__{} = right) do
    merged_booleans =
      Enum.reduce(@boolean_fields, %{}, fn field, acc ->
        Map.put(acc, field, Map.get(left, field) and Map.get(right, field))
      end)

    struct(__MODULE__, Map.put(merged_booleans, :storage_type, left.storage_type))
  end

  @doc """
  Queries a backend's capabilities by calling its `capabilities/1` callback.

  Returns the capabilities reported by the storage backend for the given state.

  ## Examples

      iex> state = ExDatalog.Storage.Map.init(%{"rel" => %{arity: 2, types: [:integer, :string]}})
      iex> caps = ExDatalog.Capabilities.from_backend({ExDatalog.Storage.Map, state})
      iex> caps.storage_type
      :map
      iex> caps.arithmetic_constraints
      true

  """
  @spec from_backend({atom(), term()}) :: t()
  def from_backend({storage_mod, state}) when is_atom(storage_mod) do
    storage_mod.capabilities(state)
  end

  @doc """
  Checks whether a capability struct satisfies a set of requirements.

  `requirements` is a keyword list of boolean fields that must all be `true`
  in the capability struct. Returns `true` if every requirement is met,
  `false` otherwise.

  ## Examples

      iex> caps = %ExDatalog.Capabilities{arithmetic_constraints: true, indexed_lookup: true}
      iex> ExDatalog.Capabilities.satisfies?(caps, arithmetic_constraints: true, indexed_lookup: true)
      true
      iex> ExDatalog.Capabilities.satisfies?(caps, arithmetic_constraints: true, concurrent_reads: true)
      false
      iex> ExDatalog.Capabilities.satisfies?(caps, [])
      true

  """
  @spec satisfies?(t(), keyword()) :: boolean()
  def satisfies?(%__MODULE__{} = caps, requirements) when is_list(requirements) do
    Enum.all?(requirements, fn {field, required} ->
      Map.get(caps, field) == required
    end)
  end
end
