defmodule ExDatalog.Storage do
  @moduledoc """
  Behaviour for pluggable relation storage backends.

  The storage layer holds all derived facts (the "EDB" and "IDB") and provides
  efficient membership tests, iteration, and indexed lookups for join
  evaluation.

  ## Contract

  - `init/1` receives relation schemas and returns an initial state.
  - `insert/3` and `insert_many/3` add tuples; idempotent (MapSet semantics).
  - `member?/3` and `size/2` are O(1) or O(log n) membership and cardinality.
  - `stream/2` returns an `Enumerable.t()` of all tuples for a relation.
  - `build_index/3` creates a hash index on the specified columns.
  - `get_indexed/4` retrieves tuples matching a key via a pre-built index.
  - `update_index/4` incrementally merges delta tuples into an existing index.
  - `relations/1` lists all relation names.

  Two implementations are planned:

  - `Storage.Map` (v1) — uses Maps and MapSets. Immutable, inspectable,
    excellent for <1M facts.
  - `Storage.ETS` (future) — uses ETS for off-heap storage and better
    GC behaviour at scale.
  """

  @type state :: term()
  @type relation_name :: String.t()
  @type tuple_values :: tuple()
  @type index_key :: [non_neg_integer()]
  @type key_values :: tuple()
  @type schemas :: %{relation_name => %{arity: non_neg_integer(), types: [atom()]}}

  @callback init(schemas) :: state
  @callback insert(state, relation_name, tuple_values) :: state
  @callback insert_many(state, relation_name, Enumerable.t()) :: state
  @callback member?(state, relation_name, tuple_values) :: boolean
  @callback size(state, relation_name) :: non_neg_integer
  @callback stream(state, relation_name) :: Enumerable.t()
  @callback get_indexed(state, relation_name, index_key, key_values) :: Enumerable.t()
  @callback build_index(state, relation_name, index_key) :: state
  @callback update_index(state, relation_name, index_key, Enumerable.t()) :: state
  @callback relations(state) :: [relation_name]
end
