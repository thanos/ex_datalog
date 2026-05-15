# Storage Backends

ExDatalog uses a pluggable storage layer. The `ExDatalog.Storage` behaviour
defines the contract all backends must implement. Two backends ship with the
library.

## Storage.Map

The default backend. Uses immutable Elixir Maps and MapSets. Thread-safe by
default, easy to inspect, and suitable for workloads under ~100K facts.

- Storage is on-heap; subject to GC pressure at scale.
- `stream/2` returns a deterministically sorted list via `Enum.sort/1`.
- `teardown/1` is a no-op (data is garbage-collected automatically).

## Storage.ETS

Uses ETS for off-heap storage. Better GC behaviour for large fact sets and
supports concurrent read access. Suitable for workloads exceeding ~100K facts.

- Tables use `:set` type with **wrapped tuple keys** (`{{:alice, :bob}}`) to
  avoid first-element collisions. Sorted `stream/2` guarantees deterministic
  ordering matching `Storage.Map`. See the moduledoc for rationale.
- Table names follow `ex_datalog_<relation>` and `ex_datalog_idx_<relation>`
  for observability in `:observer`.
- `init/2` accepts options: `:access` (`:private` default, `:public`),
  `:write_concurrency`, `:read_concurrency`.
- `teardown/1` deletes all ETS tables. After teardown, any operation raises
  `ArgumentError` with a clear message.

## Options

Pass storage options to the engine:

```elixir
{:ok, result} = Naive.evaluate(ir, storage: ExDatalog.Storage.ETS, storage_opts: [access: :public])
```

## Determinism Guarantee

All backends **must** guarantee deterministic iteration order from `stream/2`.
Identical programs with identical facts produce identical results regardless of
the backend's internal data structure ordering.

## Indexing

The indexing callbacks (`build_index/3`, `get_indexed/4`, `update_index/4`) are
optional (`@optional_callbacks`). The default `Engine.Naive` does not use them.
They exist for alternative engine implementations that can benefit from indexed
lookups during join evaluation.

## Capabilities

Each backend reports its capabilities via `capabilities/1`, returning a
`%ExDatalog.Capabilities{}` struct. Capabilities include:

| Field | Description |
|---|---|
| `storage_type` | `:map`, `:ets`, or `:external` |
| `indexed_lookup` | Supports hash-based indexed lookups |
| `concurrent_reads` | Safe for concurrent read access |
| `arithmetic_constraints` | Supports arithmetic constraints |
| `comparison_constraints` | Supports comparison constraints |
| `type_predicates` | Supports type-check predicates |
| `string_predicates` | Supports string predicates |
| `provenance` | Supports derivation provenance tracking |
| `external_execution` | Reserved for external solvers (Z3, Soufflé) |