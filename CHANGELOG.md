# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Tuple shorthand for rules**: `Program.add_rule/3` and `Program.add_rule/4` accept
  `{relation, [terms]}` tuples for heads, `{:polarity, {relation, [terms]}}` for body
  literals, and `{:op, args...}` for constraints. Uppercase atoms (`:X`) become variables,
  `:_` becomes a wildcard, lowercase atoms and other values become constants.
- `Term.from/1` — converts shorthand values to `Term.t()` following Prolog convention.
- `ExDatalog.Atom.from_tuple/1` — constructs an atom from `{"relation", [terms]}` shorthand.
- `Constraint.from_tuple/1` — constructs a constraint from operator tuples
  like `{:neq, :A, :B}`, `{:add, :X, :Y, :Z}`, `{:is_integer, :V}`.

## [0.2.0] - 2025-05-15

### Added

- Constraint types: type predicates (`type_integer/1`, `type_binary/1`, `type_atom/1`), string predicates (`starts_with/2`, `contains/2`), and membership (`member/2`)
- Constraint evaluation dispatch via `ExDatalog.Constraint.evaluate/3` with behaviour-based constraint modules
- `ExDatalog.Constraint.Context` carries storage backend capabilities through evaluation pipeline
- `ExDatalog.Capabilities` struct and merge/satisfies/from_backend API
- `ExDatalog.Storage.ETS` backend with per-relation ETS tables, wrapped-tuple keys, and concurrent read support
- Storage behaviour `init/2` for passing backend options (access, write_concurrency, read_concurrency)
- `ExDatalog.IR.from_term/1` now tags list constants as `{:const, {:list, [...]}}` for uniform IR value representation
- `ExDatalog.IR.resolve_operand/2` and `ExDatalog.IR.value_to_native/1` shared helpers for constraint evaluation
- Portability test suite (Map vs ETS) covering transitive closure, arithmetic, comparison, negation, type predicates, string predicates, and membership
- Backend conformance macro (`ExDatalog.Storage.BackendConformance`) for shared storage contract tests
- Engine `storage_opts` option for passing options to storage backends
- `try/after` resource cleanup in `Engine.Naive` for ETS teardown safety
- ETS tombstone guard (`guard_not_tombstoned!`) for clear errors on post-teardown operations
- `Constraint.valid?/1` now requires `{:const, list}` for `:member` right operand
- Validator safety tests for type, string, and membership constraint ops
- Public-struct `evaluate/3` dispatch tests for comparison, arithmetic, type, string, membership
- ETS teardown guard test and idempotent teardown test
- Doctests on `Constraint.Context.new/0,1,2`
- Documentation: `docs/constraints.md` and `docs/storage_backends.md`

### Changed

- `Storage.ETS.member?/3` now uses `:ets.member/2` (was `:ets.match_object/3`) — correct O(1) lookup
- `Storage.ETS.init/2` now accepts `write_concurrency` and `read_concurrency` options
- `Storage.ETS.upsert_index_entry` uses `MapSet` instead of lists for O(log n) membership checks
- `Storage.ETS` tables named `ex_datalog_<relation>` and `ex_datalog_idx_<relation>` for observability in `:observer`
- `Storage.ETS.update_index/4` raises `ArgumentError` on unknown relations (was silent no-op)
- `Storage.Map.update_index/4` raises `ArgumentError` on unknown relations (was silent empty-index)
- Both backends now report `type_predicates: true` and `string_predicates: true` in capabilities
- `Constraint.evaluate/3` public-struct clause delegates to IR clause via recursion; documented both dispatch paths
- `IR.from_term({:const, list})` now produces `{:const, {:list, [tagged_elements]}}` instead of `{:const, list}`
- `IR.from_constraint/1` uses `maybe_from_term/1` pattern matching instead of bare `if`
- `Constraints.Arithmetic.apply_arithmetic` uses guard clauses with integer checks
- All constraint modules use shared `IR.resolve_operand/2` and `IR.value_to_native/1` (was 5x duplicated)
- `Engine.Naive.evaluate/2` wraps evaluation in `try/after` to ensure ETS teardown on exceptions
- `Storage.ETS.teardown/1` returns `:ok` (was returning stale struct); post-teardown operations raise `ArgumentError`
- `Telemetry.emit_stop/5` requires explicit `storage_type` argument (removed default `:map`)
- Constraint behaviour callback uses `Binding.t()` instead of `map()` for type safety
- Storage behaviour `teardown` callback return type widened to `:ok | {:error, term()}`
- `Constraints.String` renamed to `Constraints.StringPredicate` to avoid stdlib `String` conflict
- `Constraint.Context` threads real storage capabilities from engine through evaluator
- `Engine.Naive` extracts `build_result/8` and `emit_result_telemetry/5` helpers from `do_evaluate_inner`
- Backend conformance macro no longer injects `alias` or `@schemas` into caller module
- Dispatch table documented as closed (not a runtime registry)
- `Capabilities.from_backend/1` spec widened from `{module(), term()}` to `{atom(), term()}`
- `Engine.Evaluator.eval_rule_iteration/5` accepts `Constraint.Context` and passes to constraint evaluation
- `ConstraintEval.apply/3` and `apply_one/3` accept optional `Constraint.Context` parameter
- `Storage.Map.size/2` and `Storage.ETS.size/2` log `Logger.debug` for unknown relations
- ETS moduledoc includes rationale for choosing `:set` table type
- `@optional_callbacks` for `build_index/3`, `get_indexed/4`, `update_index/4` in Storage behaviour
- Dispatch consistency tests verify all 16 ops dispatch correctly and `valid?/1` covers every category
- "Defines exactly 12 callbacks" test removed from storage tests (was fragile)

### Fixed

- `Storage.ETS.member?/3` was using `:ets.match_object/3` instead of `:ets.member/2` — wrong and slower
- ETS tests "returns same state struct" removed — they enforced a misleading identity invariant
- `Constraint.valid_right?(:member, ...)` now requires `{:const, list}` — prevents silent runtime filter
- Capabilities doctest for `from_backend/1` now uses valid Elixir instead of `...` ellipsis

## [0.1.0] - 2025-04-18

### Added

- Phase 0: Architecture and design blueprint (pure Elixir, semi-naive evaluation, storage behaviour, hash-join indexing primitives)
- Phase 1: AST, DSL, and term model
  - `ExDatalog.Term` — `var/1`, `const/1`, `wildcard/0`, guards, and validation
  - `ExDatalog.Constraint` — comparison (`gt`, `lt`, `gte`, `lte`, `eq`, `neq`) and arithmetic (`add`, `sub`, `mul`, `div`) constructors
  - `ExDatalog.Atom` — relation references with terms
  - `ExDatalog.Rule` — `%Rule{head, body, constraints}` with polarity on body literals
  - `ExDatalog.Program` — builder pipeline (`new/0`, `add_relation/3`, `add_fact/2`, `add_rule/2`)
  - `ExDatalog.Validator` — Phase 1 structural validation (arity, relation existence, term validity)
  - `ExDatalog.Validator.Error` — structured error types with kind, context, and message
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
  - `ExDatalog.Knowledge` — knowledge base struct with relations, stats, and provenance fields
  - Full pipeline: `ExDatalog.materialize/2` public API
- Phase 5: Negation and stratification
  - Negative body atoms (`{:negative, %IR.Atom{}}`) evaluated as filters against fully-materialised lower-stratum relations
  - Stratification validation rejects unstratifiable programs before evaluation
  - Per-stratum fixpoint iteration with timeout and iteration limits (`:max_iterations`, `:timeout_ms`)
- Phase 6: Provenance / explain
  - `ExDatalog.Explain` — derivation attribution when `explain: true` option is passed
  - `result.provenance.fact_origins` — maps each derived tuple to a rule that produced it (last-wins; not guaranteed canonical)
  - `result.provenance.rules` — rule map for human-readable rule lookup
  - Zero-overhead when `explain: false` (default): provenance tracking is entirely skipped
- Phase 7: Telemetry
  - `ExDatalog.Telemetry` — `:telemetry` event emission at evaluation start, stop, and exception
  - Events: `[:ex_datalog, :query, :start]`, `[:ex_datalog, :query, :stop]`, `[:ex_datalog, :query, :exception]`
  - Measurements: `system_time`, `duration`, `iterations`
  - Metadata: `relation_count`, `stratum_count`, `relation_sizes`, `kind`, `reason`, `stacktrace`
- Documentation: [What is Datalog?](docs/what-is-datalog.md) guide covering history, concepts, industry use cases, and LLM integration patterns

### Changed

- `Program.add_fact/3` validates fact values, rejecting floats and non-ground types with descriptive error messages
- `Program.add_relation/3`, `add_fact/3`, and `add_rule/2` propagate `{:error, _}` through pipelines instead of raising `FunctionClauseError`
- `Validator.validate/1` no longer mutates the program struct; `validate/1` is now idempotent (`program == elem(validate(program), 1)`)
- `Compiler.compile/1` normalizes facts/rules order independently (was previously done by `validate/1`)
- `Compiler.compile/1` validates IR invariants after compilation (unique rule IDs, stratum bounds, relation references, rule-in-stratum consistency)
- `Engine.Evaluator.eval_rule_iteration/4` skips variant evaluation when the delta relation is empty, avoiding wasted join work
- `Engine.Naive.iterate/1` uses incremental `merge_new/2` instead of full-storage `snapshot_facts/3` per iteration
- `IR.Constraint.serialize/1` always includes the `:result` key (even when `nil`), making the format lossless
- `ExDatalog.Atom.variables/1` now deduplicates variable names (was previously returning duplicates for `r(X, X)`)
- `Constraint.result_variable/1` has a catchall clause instead of only matching `{:var, name}` and `nil`
- `Constraint.div/3` documented as integer division (`Kernel.div/2`), not float division
- `Validator.check_atom/4` fetches the relation schema once and passes it to arity checking, avoiding redundant `Map.fetch`
- Storage indexing API (`build_index/3`, `update_index/4`, `get_indexed/4`, `Join.join_indexed/4`) marked `@doc false` for v0.1.0

### Fixed

- `Program.add_fact/3` now rejects float values and non-ground term tuples with clear error messages (previously: silent acceptance, crash at compile time)
- `Term.const/1` raises `ArgumentError` (not `FunctionClauseError`) for unsupported value types including floats
- `Validator.validate/1` returns the original program struct unchanged, fixing two invariants: `validate/1` is now idempotent, and `validate → add_rule → validate` no longer produces interleaved rule order
- `Engine.Evaluator.eval_rule_iteration/4` deduplicates k=0 fact rule results against existing tuples (was returning unfiltered results)
- `Engine.Naive.derive/5` computes derivation and origins in a single pass, eliminating 2x evaluation overhead when `explain: true`

[0.1.0]: https://github.com/anomalyco/ex_datalog/releases/tag/v0.1.0