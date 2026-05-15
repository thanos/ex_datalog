# ExDatalog

A production-grade Datalog engine for Elixir.

ExDatalog implements bottom-up Datalog evaluation using semi-naive fixpoint
computation. Programs are built with a declarative builder API, validated,
compiled to an engine-neutral IR, and evaluated by a pluggable backend.

[![Hex.pm](https://img.shields.io/hexpm/v/ex_datalog.svg)](https://hex.pm/packages/ex_datalog)
[![Hex.pm](https://img.shields.io/hexpm/dt/ex_datalog.svg)](https://hex.pm/packages/ex_datalog)
[![Hex.pm](https://img.shields.io/hexpm/l/ex_datalog.svg)](https://hex.pm/packages/ex_datalog)
[![HexDocs.pm](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/ex_datalog)
[![Coverage Status](https://coveralls.io/repos/github/thanos/ex_datalog/badge.svg?branch=main)](https://coveralls.io/github/thanos/ex_datalog?branch=main)

**New to Datalog?** Read the [What is Datalog?](docs/what-is-datalog.md) guide
for a comprehensive introduction covering history, concepts, industry use cases,
and how Datalog can serve as a knowledge layer for LLMs.

### Why Datalog Matters

Datalog remains one of the most elegant ways to express:

- recursive queries;
- graph traversal;
- rule-based systems;
- derived knowledge;
- dependency analysis;
- provenance tracking;
- temporal reasoning;
- incremental computation.

It continues to influence modern databases, compilers, static analysis tools, knowledge graphs, authorization systems, and AI reasoning engines.

## Features

- **Builder API** for constructing programs (relations, facts, rules, constraints)
- **Constraint types**: comparisons, arithmetic, type predicates, string predicates, membership
- **Negation** with stratified evaluation
- **Recursive rules** with semi-naive fixpoint evaluation
- **Pluggable storage backends**: `Storage.Map` (default, on-heap) and `Storage.ETS` (off-heap, concurrent reads)
- **Provenance / derivation explain** (`explain: true`)
- **Telemetry** integration (`:telemetry` events for query lifecycle)
- **Deterministic**: same program + same facts = same result regardless of backend
- 601 tests, 0 failures, credo clean, dialyzer clean

## Installation

Add `ex_datalog` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_datalog, "~> 0.2.0"}
  ]
end
```

## Quick Start

### Transitive closure

The classic Datalog example: compute all ancestors from parent facts.

```elixir
alias ExDatalog
alias ExDatalog.{Program, Rule, Atom, Term}

{:ok, result} =
  Program.new()
  |> Program.add_relation("parent", [:atom, :atom])
  |> Program.add_relation("ancestor", [:atom, :atom])
  |> Program.add_fact("parent", [:alice, :bob])
  |> Program.add_fact("parent", [:bob, :carol])
  |> Program.add_fact("parent", [:carol, :dave])
  |> Program.add_rule(
       Rule.new(
         Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
         [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
       )
     )
  |> Program.add_rule(
       Rule.new(
         Atom.new("ancestor", [Term.var("X"), Term.var("Z")]),
         [
           {:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])},
           {:positive, Atom.new("ancestor", [Term.var("Y"), Term.var("Z")])}
         ]
       )
     )
  |> ExDatalog.query()

result.relations["ancestor"]
#=> MapSet.new([{:alice, :bob}, {:bob, :carol}, {:carol, :dave},
#=>             {:alice, :carol}, {:bob, :dave}, {:alice, :dave}])
```

### Arithmetic constraints

Compute derived values in rules. Find numbers and their doubles:

```elixir
{:ok, result} =
  Program.new()
  |> Program.add_relation("number", [:integer])
  |> Program.add_relation("doubled", [:integer, :integer])
  |> Program.add_fact("number", [1])
  |> Program.add_fact("number", [2])
  |> Program.add_fact("number", [3])
  |> Program.add_rule(
       Rule.new(
         Atom.new("doubled", [Term.var("X"), Term.var("Y")]),
         [{:positive, Atom.new("number", [Term.var("X")])}],
         [Constraint.add(Term.var("X"), {:const, 2}, Term.var("Y"))]
       )
     )
  |> ExDatalog.query()

result.relations["doubled"]
#=> MapSet.new([{1, 3}, {2, 4}, {3, 5}])
```

### Type predicates and membership

Filter bindings by Elixir type or list membership:

```elixir
# Keep only integer values from a mixed-type relation
Rule.new(
  Atom.new("int_value", [Term.var("X")]),
  [{:positive, Atom.new("value", [Term.var("X")])}],
  [Constraint.type_integer(Term.var("X"))]
)

# Keep only "primary" colors
Rule.new(
  Atom.new("primary_color", [Term.var("X")]),
  [{:positive, Atom.new("color", [Term.var("X")])}],
  [Constraint.member(Term.var("X"), {:const, [:red, :blue, :green]})]
)

# Keep only strings that start with "hel"
Rule.new(
  Atom.new("hello_word", [Term.var("X")]),
  [{:positive, Atom.new("word", [Term.var("X")])}],
  [Constraint.starts_with(Term.var("X"), {:const, "hel"})]
)
```

### Negation

Use negative body atoms with stratified evaluation. Find people who are not parents:

```elixir
Program.add_rule(
  Rule.new(
    Atom.new("childless", [Term.var("X")]),
    [
      {:positive, Atom.new("person", [Term.var("X")])},
      {:negative, Atom.new("parent", [Term.var("X"), Term.wildcard()])}
    ]
  )
)
```

### ETS backend

For workloads exceeding ~100K facts, use the ETS backend for off-heap storage
and reduced GC pressure:

```elixir
{:ok, result} = ExDatalog.query(program, storage: ExDatalog.Storage.ETS)

# Or with options:
{:ok, result} =
  ExDatalog.query(program,
    storage: ExDatalog.Storage.ETS,
    storage_opts: [access: :public, write_concurrency: true]
  )
```

### Provenance / explain

Track which rule derived each fact:

```elixir
{:ok, result} = ExDatalog.query(program, explain: true)
result.provenance.fact_origins
#=> %{"ancestor" => %{{:alice, :bob} => "rule_0", ...}, ...}
```

### Telemetry

ExDatalog emits `:telemetry` events at the start, end, and on exceptions
during query evaluation:

```elixir
:telemetry.attach("my-handler", [:ex_datalog, :query, :stop], &handle_stop/4, nil)

def handle_stop(_event, measurements, metadata, _config) do
  IO.puts("Query completed in #{measurements.duration} µs (#{measurements.iterations} iterations)")
  IO.puts("Storage backend: #{metadata.storage_type}")
end
```

## Architecture

```
ExDatalog.Program  (builder)
        |
        v
ExDatalog.Validator  (structural + semantic + stratification)
        |
        v
ExDatalog.Compiler  (AST -> IR)
        |
        v
ExDatalog.Engine  (behaviour)
        |
        v
ExDatalog.Engine.Naive  (semi-naive fixpoint)
        |
        v  uses
ExDatalog.Storage.Map | ExDatalog.Storage.ETS
        |
        v
ExDatalog.Result
```

The `Storage` behaviour defines the contract for pluggable backends.
`Storage.Map` uses on-heap Maps and MapSets; `Storage.ETS` uses per-relation
ETS tables with wrapped-tuple keys for O(1) membership and correct set
semantics. Both guarantee deterministic output order from `stream/2`, so
identical programs produce identical results on either backend.

Constraint evaluation dispatches through `ExDatalog.Constraint.evaluate/3`,
which routes to the appropriate module (`Comparison`, `Arithmetic`, `Type`,
`StringPredicate`, `Membership`) based on the constraint's `op` field. The
evaluation context carries the storage backend's capabilities, enabling
future constraint types to inspect them.

## Storage backends

| Backend | Storage | Best for | Concurrent reads |
|---|---|---|---|
| `Storage.Map` | On-heap Maps/MapSets | <100K facts | No |
| `Storage.ETS` | Per-relation ETS tables | >100K facts, GC relief | Yes (with `access: :public`) |

Both backends produce **identical output** for the same program and facts.
The portability test suite verifies this for transitive closure, arithmetic,
comparison, negation, type predicates, string predicates, and membership
constraints.

See [docs/storage_backends.md](docs/storage_backends.md) for the full
backend contract, options, and capability model.

## Constraints

See [docs/constraints.md](docs/constraints.md) for the complete constraint
reference.

| Category | Ops | Binds result? |
|---|---|---|
| Comparison | `gt`, `lt`, `gte`, `lte`, `eq`, `neq` | No (filter) |
| Arithmetic | `add`, `sub`, `mul`, `div` | Yes |
| Type predicate | `type_integer`, `type_binary`, `type_atom` | No (filter) |
| String predicate | `starts_with`, `contains` | No (filter) |
| Membership | `member` | No (filter) |

## Documentation

- [What is Datalog?](docs/what-is-datalog.md) — introduction, history, Prolog comparison, industry use cases, LLM integration
- [Constraints](docs/constraints.md) — constraint types, evaluation, and the dispatch model
- [Storage Backends](docs/storage_backends.md) — Map vs ETS, options, capabilities, determinism guarantee
- [API reference](https://hexdocs.pm/ex_datalog) — full module and function documentation

Generate docs locally:

```
mix docs
```




## Further Reading on Datalog

Datalog sits at the intersection of databases, logic programming, graph reasoning, and knowledge systems.  
The following references are highly recommended for understanding both the theory and practice behind modern Datalog systems.

- [What is Datalog?](docs/what-is-datalog.md) — this project's in-depth guide
- [Souffle's Datalog Tutorial](https://souffle-lang.github.io/tutorial)
- [MICHELIN's introduction to Datalog](https://blogit.michelin.io/an-introduction-to-datalog/)
- [Philip Zucker's Detailed Tutorial](https://www.philipzucker.com/notes/Languages/datalog/)
### Modern Datalog Systems

- [DataScript](https://github.com/tonsky/datascript)
  - Immutable in-memory Datalog database for Clojure and JavaScript.
  - Excellent examples of practical Datalog query design.

- [XTDB](https://xtdb.com/)
  - Bitemporal document database with a powerful Datalog query engine.
  - Demonstrates how Datalog can power modern data-intensive systems.

- [Soufflé](https://souffle-lang.github.io/)
  - High-performance Datalog engine widely used in static analysis and security research.
  - Excellent resource for understanding scalable and compiled Datalog execution.

- [Differential Datalog (DDlog)](https://github.com/vmware/differential-datalog)
  - Incremental and streaming-oriented Datalog system built on differential dataflow.
  - Useful for understanding reactive and continuously updated derived state.

---

### Foundational Theory

- [Stanford Datalog Notes](http://infolab.stanford.edu/~ullman/fcdb/aut07/slides/dlog.pdf)
  - Clear academic introduction to recursive query processing, semantics, and evaluation strategies.

- [Foundations of Databases — Abiteboul, Hull, Vianu](http://webdam.inria.fr/Alice/)
  - Classic database theory text covering relational algebra, recursion, logic, and Datalog semantics.

---

### Talks and Presentations

- [Rich Hickey — Datomic and Datalog Talks](https://www.youtube.com/results?search_query=rich+hickey+datalog+datomic)
  - Deep insights into immutable facts, identity, temporal data, and relational thinking.

- [XTDB Conference Talks](https://www.youtube.com/results?search_query=xtdb+datalog)
  - Practical production-oriented discussions around Datalog, event sourcing, and knowledge systems.

---



## Roadmap

| Version | Description |
|---|---|
| v0.2.0 | ETS backend, constraint behaviour, type/string/membership predicates, capabilities, provenance, telemetry |
| v0.3.0 | Aggregation (`count`, `sum`, `min`, `max`), general predicates as deterministic BEAM callbacks |
| v0.4.0 | Magic sets / demand-driven evaluation, external solver adapter (experimental Z3/Soufflé) |
| v1.0.0 | Stable public API, hardened production semantics |

## License

MIT
