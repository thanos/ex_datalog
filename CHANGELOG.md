# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Unreleased

### Added

- Phase 0: Architecture and design blueprint (pure Elixir, semi-naive evaluation, storage behaviour, hash-join indexing primitives)
- Phase 1: AST, DSL, and term model
  - `ExDatalog.Term` — `var/1`, `const/1`, `wildcard/0`, guards, and validation
  - `ExDatalog.Constraint` — comparison (`gt`, `lt`, `gte`, `lte`, `eq`, `neq`) and arithmetic (`add`, `sub`, `mul`, `div`) constructors
  - `ExDatalog.Atom` — relation references with terms
  - `ExDatalog.Rule` — `%Rule{head, body, constraints}` with polarity on body literals
  - `ExDatalog.Program` — builder pipeline (`new/0`, `add_relation/3`, `add_fact/2`, `add_rule/2`)
  - `ExDatalog.Validator` — Phase 1 structural validation (arity, relation existence, term validity)
  - `ExDatalog.Validator.Errors` — structured error types with kind, context, and message
- Phase 2: Semantic validation
  - `ExDatalog.Validator.Safety` — variable safety and range-restriction checks (all head variables appear in a positive body atom)
  - `ExDatalog.Validator.Stratification` — Tarjan SCC-based stratification (detects unstratifiable negation cycles)
  - Chained validation pipeline: structural → safety → stratification
- Phase 3: IR compiler
  - `ExDatalog.Compiler` — AST-to-IR compilation producing `IR.Program` with strata, rules, facts, and relation schemas
  - `ExDatalog.Compiler.Stratifier` — Tarjan SCC algorithm to assign strata and detect unstratifiable programs
  - `ExDatalog.IR` — engine-neutral IR structs: `IR.Program`, `IR.Stratum`, `IR.Rule`, `IR.Atom`, `IR.Fact`, `IR.Constraint`
- Phase 4: Semi-naive engine
  - `ExDatalog.Engine.Naive` — semi-naive fixpoint evaluation with k-position delta computation
  - `ExDatalog.Engine.Evaluator` — single-rule evaluation with k-position delta variants
  - `ExDatalog.Engine.Binding` — binding environment operations (lookup, extend, ir_value_to_native)
  - `ExDatalog.Engine.Join` — sequential-scan join (`join/3`), tuple matching (`match_tuple/3`), projection (`project/2`), indexed join (`join_indexed/4`, not yet wired into evaluator)
  - `ExDatalog.Engine.ConstraintEval` — constraint evaluation (comparison filters, arithmetic extensions)
  - `ExDatalog.Storage.Map` — default Map/MapSet-based storage backend
  - `ExDatalog.Result` — result struct with relations, stats, and provenance fields
  - Full pipeline: `ExDatalog.query/1` and `ExDatalog.query/2` public API
- Phase 5: Negation and stratification
  - Negative body atoms (`{:negative, %IR.Atom{}}`) evaluated as filters against fully-materialised lower-stratum relations
  - Stratification validation rejects unstratifiable programs before evaluation
  - Per-stratum fixpoint iteration with timeout and iteration limits (`:max_iterations`, `:timeout_ms`)
- Phase 6: Provenance / explain
  - `ExDatalog.Explain` — derivation attribution when `explain: true` option is passed
  - `result.provenance.fact_origins` — maps each derived tuple to the rule that produced it (last-wins)
  - `result.provenance.rules` — rule map for human-readable rule lookup
  - Zero-overhead when `explain: false` (default): provenance tracking is entirely skipped
- Phase 7: Telemetry
  - `ExDatalog.Telemetry` — `:telemetry` event emission at evaluation start, stop, and exception
  - Events: `[:ex_datalog, :query, :start]`, `[:ex_datalog, :query, :stop]`, `[:ex_datalog, :query, :exception]`
  - Measurements: `system_time`, `duration`, `iterations`
  - Metadata: `relation_count`, `stratum_count`, `relation_sizes`, `kind`, `reason`, `stacktrace`

### Internal

- Storage indexing API (`build_index/3`, `update_index/4`, `get_indexed/4`, `Join.join_indexed/4`) implemented and tested but not wired into `Engine.Evaluator`; marked `@doc false` for v0.1.0
- Fixpoint evaluation avoids double evaluation when provenance is enabled (merged `derive_all`/`derive_origins` into single `derive/5` pass)

[0.1.0]: https://github.com/anomalyco/ex_datalog/releases/tag/v0.1.0