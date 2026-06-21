# Negation, Constraints, and Safety: Stratified Evaluation in ExDatalog

Datalog without negation is monotonic: facts can only be added, never retracted. Real programs need negation — "find people who are not parents," "detect unmatched transactions." But adding negation to a recursive program creates a problem: the evaluation order of negated literals affects the result, and negation cycles can make the result undefined.

ExDatalog solves this with stratified negation — a well-established technique from database theory — backed by variable safety rules that prevent unsound programs from running.

## The `not_` Macro and Negative Literals

In the Schema DSL, negation is expressed with `not_`:

```elixir
rule bachelor(P) do
  male(P)
  not_ married(P, _)
end
```

The DSL desugars this into `{:negative, %ExDatalog.Atom{}}` — a body literal with explicit polarity. During evaluation, the engine checks whether a binding from the positive atoms (`male(P)`) is contradicted by any matching tuple in the negated relation (`married`). If a match exists, the binding is rejected; otherwise, it passes.

## Stratification: Tarjan's Algorithm

Negation requires that the negated relation be fully computed before the rule fires. ExDatalog's `Validator.Stratification` module builds a dependency graph where each rule creates edges from its head relation to each body relation, tagged with polarity:

```elixir
bachelor → male (positive)
bachelor → married (negative)
```

The module computes strongly connected components (SCCs) using Tarjan's algorithm. If any SCC contains a negative edge, the program is unstratifiable and is rejected:

```elixir
defp check_scc_negation(scc, graph) do
  scc_set = MapSet.new(scc)
  scc
  |> Enum.flat_map(fn rel ->
    deps = Map.get(graph, rel, [])
    Enum.filter(deps, fn {dep, polarity} ->
      polarity == :negative and MapSet.member?(scc_set, dep)
    end)
  end)
end
```

The compiler then assigns each relation a stratum — the lowest stratum such that all negative dependencies belong to strictly lower strata. During evaluation, `Engine.Naive` processes strata sequentially:

```elixir
{state_final, total_iterations, origins, termination} =
  eval_strata(state, ir.strata, ir.rules, max_iterations, ...)
```

Each stratum runs to a local fixpoint before the next begins, guaranteeing that negated relations are complete.

## The Constraint DSL

Constraints are built-in predicates that filter or extend bindings during rule evaluation. They appear in rule bodies alongside relational atoms:

```elixir
rule high_earner(P) do
  income(P, S)
  gt(S, 100_000)
end
```

The DSL desugars `gt(S, 100_000)` into `%Constraint{op: :gt, left: {:var, "S"}, right: {:const, 100_000}, result: nil}`. Five categories exist:

| Category | Ops | Binds result? |
|---|---|---|
| Comparison | `gt`, `lt`, `gte`, `lte`, `eq`, `neq` | No — filters |
| Arithmetic | `add`, `sub`, `mul`, `div` | Yes — binds result variable |
| Type predicate | `is_integer`, `is_binary`, `is_atom` | No — filters |
| String predicate | `starts_with`, `contains` | No — filters |
| Membership | `member` | No — filters |

Arithmetic constraints are special: they introduce new variable bindings. In `add(B, 20, T)`, the result variable `T` is computed and added to the binding environment, making it available for the rule head even though it doesn't appear in any positive body atom.

## Variable Safety Rules

ExDatalog enforces three safety rules:

**1. Head variables must be bound.** Every variable in the rule head must appear in a positive body atom or be an arithmetic result variable. This rejects `ancestor(X, Z) :- parent(X, Y)` because `Z` is unbound.

**2. Constraint inputs must be bound before use.** Constraints are validated sequentially. A comparison's inputs must be bound by positive body atoms or by *earlier* arithmetic results:

```elixir
# Safe: Z is bound by the first constraint
total(X, Z) :- value(X, A), add(A, 1, Z)

# Unsafe: W references Z before Z is computed
bad(X, W) :- value(X, A), add(W, 1, Z), add(A, 2, Z)
```

**3. No wildcards in rule heads.** Wildcards match anything without binding, so they can't appear in the head position.

The safety checker processes constraints in order, threading the bound set:

```elixir
{errors, _final_bound} =
  constraints
  |> Enum.with_index()
  |> Enum.reduce({errors, body_bound}, fn {c, c_idx}, {acc_errors, bound} ->
    check_constraint(c, c_idx, bound, rule_index, acc_errors)
  end)
```

Arithmetic constraints extend the bound set with their result variable, making it available for subsequent constraints. This sequential threading means constraint order matters — just as it does in Datalog's evaluation model.

## Negation and Safety Interaction

Variables that appear only in negative body atoms are **not** bound. This means:

```elixir
rule invalid(X) do
  not_ married(X, _)  # ERROR: X not bound by any positive atom
end
```

The fix is to add a positive atom that binds the variable:

```elixir
rule bachelor(X) do
  male(X)             # binds X
  not_ married(X, _)  # OK: X is already bound
end
```

This is the range-restriction property: every head variable must be bound by a positive body atom or an arithmetic constraint. Negative atoms can only filter — they cannot introduce new bindings.

## What's Coming in v0.5.0

- **Aggregates** — the syntax `agg(:count, X)` is already parsed but returns `%UnsupportedFeature{feature: :aggregates}`. The implementation will add count, sum, min, and max with proper safety checks.
- **Magic sets / demand-driven evaluation** — goal-directed evaluation that computes only facts relevant to a specific query, instead of the full fixpoint.
- **General predicates as BEAM callbacks** — arbitrary Elixir functions as predicates, extending Datalog's reasoning with Elixir's computation while maintaining stratification and safety.

These features will expand what's expressible while preserving Datalog's guarantees: termination, deterministic output, and compile-time validation.