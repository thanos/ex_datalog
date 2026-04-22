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
domain-specific examples (fraud detection, supply chain, social networks,
infrastructure), and how Datalog can serve as a knowledge layer for LLMs.

## Features

- Builder API for constructing programs (relations, facts, rules)
- Full term model: variables, constants, wildcards
- Built-in predicates: comparisons (`>`, `<`, `>=`, `<=`, `=`, `!=`) and arithmetic (`+`, `-`, `*`, `div`)
- Negation with stratification
- Recursive rules with fixpoint evaluation
- Pluggable storage and engine backends
- Provenance / derivation explain (`explain: true`)
- Telemetry integration (`:telemetry` events)
- 369 tests, 92% coverage

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

Enable provenance tracking to see which rule derived each fact:

```elixir
{:ok, result} = ExDatalog.query(program, explain: true)
result.provenance.fact_origins
#=> %{"ancestor" => %{{:alice, :bob} => "rule_0", ...}}
```

## Negation

Use negative body atoms with stratified evaluation:

```elixir
Program.add_rule(
  Rule.new(
    Atom.new("bachelor", [Term.var("X")]),
    [
      {:positive, Atom.new("male", [Term.var("X")])},
      {:negative, Atom.new("married", [Term.var("X"), Term.wildcard()])}
    ]
  )
)
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

## Documentation

- [What is Datalog?](docs/what-is-datalog.md) — introduction, history, Prolog comparison, industry use cases, LLM integration patterns
- [API reference](https://hexdocs.pm/ex_datalog) — full module and function documentation

Generate docs locally:

```
mix docs
```

## Roadmap

All phases ship together in **v0.1.0**. The phased build approach is an
internal development discipline — each phase is independently tested and
reviewed before proceeding, but they are not separate releases.

| Phase | Name | What ships |
|---|---|---|
| 0 | Architecture & Design | System blueprint, algorithm decisions, IR specification |
| 1 | AST + DSL + Term Model | Program builder, term types, constraints, structural validation |
| 2 | Semantic Validation | Variable safety, range restriction, stratified negation detection |
| 3 | IR Compiler | AST to engine-neutral IR, Tarjan SCC stratification |
| 4 | Semi-Naive Engine | Sequential-scan fixpoint evaluation, storage abstraction, full pipeline |
| 5 | Negation + Stratification | Stratum-ordered evaluation, negative body literals |
| 6 | Explain / Provenance | Opt-in derivation attribution, rule tracing |
| 7 | Telemetry | `:telemetry` events, execution metrics |

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
ExDatalog.Storage.Map  (Maps + MapSets)
        |
        v
ExDatalog.Result
```

## License

MIT
