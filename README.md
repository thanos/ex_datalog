# ExDatalog

A production-grade Datalog engine for Elixir.

ExDatalog implements bottom-up Datalog evaluation using semi-naive fixpoint
computation. Programs are built with a declarative builder API, validated,
compiled to an engine-neutral IR, and evaluated by a pluggable backend.

## Features

- Builder API for constructing programs (relations, facts, rules)
- Full term model: variables, constants, wildcards
- Built-in predicates: comparisons (`>`, `<`, `>=`, `<=`, `=`, `!=`) and arithmetic (`+`, `-`, `*`, `/`)
- Negation with stratification
- Recursive rules with fixpoint evaluation
- Pluggable storage and engine backends
- Provenance / derivation explain (planned)
- Telemetry integration (planned)

## Quick Start

```elixir
alias ExDatalog
alias ExDatalog.{Program, Rule, Atom, Term}

{:ok, result} =
  Program.new()
  |> Program.add_relation("parent", [:atom, :atom])
  |> Program.add_relation("ancestor", [:atom, :atom])
  |> Program.add_fact("parent", [:alice, :bob])
  |> Program.add_fact("parent", [:bob, :carol])
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
```

## Installation

Add `ex_datalog` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_datalog, "~> 0.1.0"}
  ]
end
```

## Roadmap

All phases ship together in **v0.1.0**. The phased build approach is an
internal development discipline — each phase is independently tested and
reviewed before proceeding, but they are not separate releases.

### v0.1.0 — Initial Release

| Phase | Name | Status | What ships |
|---|---|---|---|
| 0 | Architecture & Design | Done | System blueprint, algorithm decisions, IR specification |
| 1 | AST + DSL + Term Model | Done | Program builder, term types, constraints, structural validation |
| 2 | Semantic Validation | In progress | Variable safety, range restriction, stratified negation detection |
| 3 | IR Compiler | Pending | AST to engine-neutral IR, Tarjan SCC stratification |
| 4 | Semi-Naive Engine | Pending | Hash-join fixpoint evaluation, storage abstraction, full pipeline |
| 5 | Negation + Stratification | Pending | Stratum-ordered evaluation, negative body literals |
| 6 | Explain / Provenance | Pending | Opt-in derivation trees, rule attribution |
| 7 | Telemetry | Pending | `:telemetry` events, execution metrics |
| 8 | Future Extensions | Pending | ETS storage, Rust NIF, incremental evaluation (design docs only) |

### Post v0.1.0

Future releases will be driven by production usage. Candidates include:

| Target | Description |
|---|---|
| v0.2.0 | ETS storage backend (`Storage.ETS`) for workloads >100K facts |
| v0.3.0 | Aggregation support (`count`, `sum`, `min`, `max`) |
| v0.4.0 | Magic sets / demand-driven evaluation for goal-directed queries |
| v1.0.0 | Stable public API, Rust NIF backend for workloads >1M facts |

## Architecture

```
ExDatalog.Program  (builder)
        |
        v
ExDatalog.Validator  (structural + semantic)
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
ExDatalog.Storage.Map  (Maps + lazy indexes)
        |
        v
ExDatalog.Result
```

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc):

```
mix docs
```
