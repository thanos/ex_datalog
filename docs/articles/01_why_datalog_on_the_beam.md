# Why Datalog Fits the BEAM VM

Datalog is a declarative logic programming language rooted in first-order logic. It computes derived facts from base facts using recursive rules, converging to a fixed point where no new facts can be produced. ExDatalog brings this model to the BEAM — Erlang's virtual machine — and the fit is more than coincidental. The BEAM's foundational design choices align with Datalog's semantics in ways that make the implementation feel natural rather than forced.

## Shared Foundations: Immutability and Pattern Matching

Datalog operates on immutable sets of facts. Once a fact is asserted, it never changes — the evaluation engine simply accumulates new derivations until reaching a fixpoint. The BEAM's runtime is built around the same principle. Elixir data structures are immutable by default; every "modification" produces a new value, and references to the old version remain valid.

This isn't just a philosophical alignment. ExDatalog's `Knowledge` struct holds each relation as a `MapSet` of tuples. During semi-naive evaluation, each iteration produces a *delta* — the set of newly derived facts. The engine merges the delta into the full fact set using `MapSet.union/2`, which returns a new set without mutating the old one. The old snapshot is preserved as `old`, and the delta is computed as `full \ old`. No defensive copying, no lock-based concurrency concerns, no risk of one iteration corrupting another's view of the database.

Pattern matching is the other shared primitive. In Datalog, a rule body like:

```elixir
rule ancestor(x, z) do
  parent(x, y)
  ancestor(y, z)
end
```

means: for every binding of `x`, `y`, `z` where `parent(x, y)` and `ancestor(y, z)` both hold, derive `ancestor(x, z)`. The engine joins relations by matching tuples against term patterns — variables bind, constants must equal, wildcards match anything. This is precisely what the BEAM's pattern matching engine does when it dispatches function clauses. ExDatalog's `Engine.Binding` module extends a binding environment by matching IR values against stored tuple positions, just as Elixir extends a function's local scope by matching a pattern against an argument.

## Recursive Evaluation and the Fixpoint

Datalog's defining computational model is the fixpoint: start with the base facts, apply every rule, collect new derivations, and repeat until nothing new emerges. This maps directly onto the BEAM's strength in managing long-running, message-driven processes — but even without processes, the fixpoint loop is a natural fit for a functional runtime.

ExDatalog's `Engine.Naive` implements the semi-naive algorithm. Each iteration considers only facts that are *new* since the last iteration (the delta), avoiding redundant derivations. The implementation is a straightforward recursive loop:

```elixir
defp fixpoint(ctx) do
  if delta_empty?(ctx.delta, ctx.all_rels) do
    ctx
  else
    iterate(ctx)
  end
end
```

The BEAM's tail-call optimization ensures this loop runs in constant stack space, even for programs requiring thousands of iterations. The default iteration limit is 10,000, configurable via `max_iterations`. Timeouts are checked each iteration using monotonic time, avoiding clock drift:

```elixir
if System.monotonic_time(:millisecond) > ctx.deadline do
  %{ctx | termination: :timeout}
```

The termination status (`:fixpoint`, `:iteration_limit`, or `:timeout`) is returned in the `Knowledge` struct's `stats` field, giving callers a clear signal about whether the result is complete.

## Hot Code Reloading and Knowledge Evolution

The BEAM's hot code reloading is one of its most distinctive features — you can upgrade a running system's code without stopping it. ExDatalog's DSL leverages this through Ecto-inspired compile-time macros. When you `use ExDatalog.Schema` and define a module like:

```elixir
defmodule AncestorRules do
  use ExDatalog.Schema

  relation :parent do
    field :parent, :atom
    field :child, :atom
  end

  rule ancestor(x, y) do
    parent(x, y)
  end

  rule ancestor(x, z) do
    parent(x, y)
    ancestor(y, z)
  end
end
```

The module compiles into a `program/0` function that builds the `ExDatalog.Program` struct at runtime. If you modify the rules — say, adding a new relation or changing a constraint — and hot-reload the module, the next call to `AncestorRules.program()` returns the updated program. The knowledge base itself is immutable; you re-materialize to get new results. This separation between the rule definition (code) and the derived knowledge (data) is exactly how Datalog is meant to work, and the BEAM's hot code reloading makes it operationally seamless.

## Stratification and Process Isolation

When Datalog programs include negation, stratification determines the evaluation order: relations appearing under negation must be fully computed before they can be negated. ExDatalog uses Tarjan's strongly connected components algorithm to compute strata at compile time, then evaluates them sequentially.

```elixir
{state_final, total_iterations, origins, termination} =
  eval_strata(state, ir.strata, ir.rules, max_iterations, ...)
```

Each stratum runs to a local fixpoint before the next one begins. This sequential dependency would be awkward in a system that assumes concurrent mutation, but on the BEAM — where processes share no memory and communicate by message passing — the isolation is inherent. The current implementation evaluates strata sequentially within a single process, but the architecture leaves room for parallelizing independent strata across BEAM processes, since each stratum's derived facts can be computed from immutable snapshots.

## Persistent Data Structures and Incremental Computation

The BEAM's immutable data structures have another advantage: they make incremental computation efficient. During semi-naive evaluation, ExDatalog maintains three snapshots per relation per iteration:

- **`full`** — all known facts
- **`delta`** — facts newly derived in the previous iteration
- **`old`** — the `full` snapshot before the current derivation step

Because Elixir's Maps and MapSets are persistent data structures, creating `old` from `full` is an O(1) pointer copy — the entire snapshot shares structure with the previous version. Computing `delta = full \ old` requires only the diff, avoiding a full scan of every relation on every iteration.

The `Storage.Map` backend stores facts directly in process heap Maps and MapSets. For workloads exceeding ~100K facts, the `Storage.ETS` backend moves data off-heap into per-relation ETS tables, reducing GC pressure while preserving the same deterministic output guarantee. Both backends produce identical `Knowledge` structs for the same program and facts.

## Why Not Prolog?

Elixir developers sometimes ask: why Datalog rather than Prolog on the BEAM? The answer is convergence. Prolog's top-down evaluation with backtracking can loop infinitely on recursive programs, and implementing a complete Prolog engine (with cut, occur-check, and tabling) is a deep undertaking. Datalog's bottom-up, ground-term-only model guarantees termination for programs without arithmetic constraints on unbounded domains, and its fixpoint semantics are simpler to implement correctly.

ExDatalog's validation pipeline catches non-terminating programs before evaluation begins. The safety checker rejects rules where head variables aren't bound by positive body atoms. The stratification checker rejects programs with unstratifiable negation cycles. These are compile-time guarantees — not runtime gambles.

The BEAM's strengths — immutability, pattern matching, hot code reloading, persistent data structures — are not just compatible with Datalog's semantics. They make Datalog on the BEAM feel like the natural expression of a logic language in a concurrent, fault-tolerant runtime. ExDatalog v0.4.0 is the first version to surface these strengths through a declarative Schema DSL, and the result is a system where writing Datalog programs feels like writing Elixir.