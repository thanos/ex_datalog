# Magic Sets and Demand-Driven Evaluation: Goal-Directed Datalog in ExDatalog

Semi-naive evaluation computes the *full* least fixpoint of a program: every derivable fact in every relation, regardless of whether anyone will ever read it. That is the right default when the materialised knowledge is reused for many queries, but it is wasteful when a single question is asked against a large dataset. "Who are the ancestors of *Alice*?" should not require deriving the ancestors of *every* person in the database first.

The **magic sets** transformation — a classic technique from deductive database theory — bridges the gap between bottom-up fixpoint evaluation and top-down goal-directed query answering. It rewrites the program so that bottom-up evaluation only derives facts relevant to a specific query goal, while keeping the engine itself untouched. ExDatalog implements it in `ExDatalog.MagicSets` as an experimental v0.5.0 feature reached through `materialize/2`'s `:strategy` option.

## Why Demand-Driven Evaluation Matters

Consider the ancestor program:

```elixir
rule ancestor(X, Y) do
  parent(X, Y)
end

rule ancestor(X, Z) do
  parent(X, Y)
  ancestor(Y, Z)
end
```

Semi-naive evaluation derives `ancestor/2` for *every* pair connected through `parent/2`. If the dataset has ten thousand people, the engine produces ten thousand ancestors tuples. But the query "ancestors of Alice" only needs the small slice `ancestor(alice, *)`. A top-down Prolog-style solver would discover that slice directly; a pure bottom-up engine cannot — it has no notion of "query."

Magic sets fixes this by *rephrasing the program* so the existing bottom-up engine derives only the requested slice. No new evaluation algorithm, no special query interpreter. The transformation introduces an auxiliary **magic** predicate that records "which bindings are we interested in?" and threads that information through every recursive rule.

## The Transform: Adornment → Magic Predicates → Seeds → Rewriting

The transformation in `ExDatalog.MagicSets.transform/2` proceeds in four stages.

### 1. Adornment

Given a goal `{relation, pattern}`, the pattern marks each argument position as **bound** (`b`) or **free** (`f`). The pattern `[:a, :_]` becomes the adornment string `"bf"`: the first position is bound to a constant, the second is unbound.

```elixir
defp adornment(pattern) do
  Enum.map_join(pattern, "", fn
    :_ -> "f"
    _ -> "b"
  end)
end
```

The adornment is the *signature* of the demand: every derived fact of the goal relation must agree with the bound positions.

### 2. Magic Predicates

The transformation synthesises a new relation named `magic_<relation>_<adornment>` — for example `magic_ancestor_bf` — whose arity is the number of bound positions. Its tuples record the *values we are asking about*. A tuple `(alice,)` in `magic_ancestor_bf` means "compute `ancestor` facts whose first argument is `alice`."

The relation is registered in the IR so the engine allocates storage for it, and its type signature is projected from the original relation's declared types:

```elixir
magic_relation = %IR.Relation{
  name: magic_rel,
  arity: bound_count(goal_pattern),
  types: bound_types(ir, goal_relation, goal_pattern)
}
new_relations = [magic_relation | ir.relations]
```

### 3. Seed Facts

The bound constants of the goal pattern are inserted as the initial magic facts — the "seeds" of demand. For `goal: {"ancestor", [:a, :]}` the seed is the single fact `magic_ancestor_bf(a)`:

```elixir
defp seed_fact(magic_rel, _goal_relation, pattern) do
  bound_values =
    pattern
    |> Enum.filter(fn p -> p != :_ end)
    |> Enum.map(&to_ir_value/1)

  case bound_values do
    [] -> nil
    values -> %IR.Fact{relation: magic_rel, values: values}
  end
end
```

Without a seed, the magic relation is empty and no goal-relation rule can fire, so nothing is derived. The seed is what kicks off demand propagation.

### 4. Rule Rewriting

Every rule whose head is the goal relation is rewritten to *consume* the magic predicate as its first body atom. Only bindings consistent with an existing magic tuple are allowed to proceed. For the recursive ancestor rule this means:

```
ancestor(X, Z) :- parent(X, Y), ancestor(Y, Z).
```
becomes
```
ancestor(X, Z) :- magic_ancestor_bf(X), parent(X, Y), ancestor(Y, Z).
```

The implementation prepends the magic atom:

```elixir
defp rewrite_rule(%IR.Rule{head: %IR.Atom{relation: rel} = head} = rule, goal_relation, magic_rel, bound_positions)
       when rel == goal_relation do
  magic_terms = bound_head_terms(head, bound_positions)
  magic_atom = %IR.Atom{relation: magic_rel, terms: magic_terms}
  %IR.Rule{rule | body: [{:positive, magic_atom} | rule.body]}
end
```

The magic atom projects exactly the goal's bound positions of the head, so its arity matches the magic relation. Rules whose head is *not* the goal relation are left untouched.

Finally, the magic relation is injected into the goal relation's stratum so the stratified evaluator processes them in the same pass:

```elixir
defp inject_magic_into_strata(strata, goal_relation, magic_rel) do
  Enum.map(strata, fn %IR.Stratum{relations: rels} = stratum ->
    if goal_relation in rels do
      %IR.Stratum{stratum | relations: [magic_rel | rels]}
    else
      stratum
    end
  end)
end
```

The transformed IR is structurally a normal Datalog program. It is handed back to the existing semi-naive engine unchanged. Magic sets is a *program rewrite*, not a new evaluator.

## Goal-Driven Evaluation

The user-facing entry point is `ExDatalog.materialize/2` with the `:strategy` and `:goal` options:

```elixir
{:ok, magic} =
  ExDatalog.materialize(program,
    strategy: :magic_sets,
    goal: {"ancestor", [:a, :_]}
 )

Knowledge.match(magic, "ancestor", [:a, :_])
```

The dispatch lives in `Engine.Naive.evaluate/2`, which switches on the `:strategy` option:

```elixir
case Keyword.get(opts, :strategy, :semi_naive) do
  :semi_naive ->
    evaluate_semi_naive(ir, opts)

  :magic_sets ->
    evaluate_magic_sets(ir, opts)
end
```

The `:magic_sets` path requires a `:goal`. If absent, the engine falls back to plain semi-naive evaluation — there is no demand to drive without a goal:

```elixir
defp evaluate_magic_sets(%IR{} = ir, opts) do
  case Keyword.get(opts, :goal, nil) do
    nil ->
      evaluate_semi_naive(ir, opts)

    goal ->
      case ExDatalog.MagicSets.transform(ir, goal) do
        {:ok, transformed_ir} ->
          evaluate_semi_naive(transformed_ir, Keyword.delete(opts, :strategy))

        {:fallback, _reason} ->
          evaluate_semi_naive(ir, opts)
      end
  end
end
```

When the transform succeeds, the **original** IR is discarded: only the transformed IR is evaluated. When the transform declines (`{:fallback, _}`), the unmodified IR is evaluated with semi-naive, so the query still produces a correct answer — just without the demand-restriction savings.

The `Planner` records the chosen strategy and goal in its `Plan` struct for telemetry and introspection, but the rewrite itself happens inside the engine, not the planner. The planner is the seam where cost-based strategy selection will eventually live.

## Bound Positions

The goal pattern's bound positions are what make demand restriction possible. `[:a, :_]` binds position 0 to the atom `:a` and leaves position 1 free. The transformation:

- names the magic predicate using the adornment `bf`,
- gives it arity 1 (one bound position),
- seeds it with `(a,)`,
- and rewrites each goal-relation rule to join `magic_ancestor_bf(<head arg 0>)` before any other body atom.

A pattern with both positions bound — `[:a, :b]` — would produce `magic_ancestor_bb` of arity 2, seeded with `(a, b)`, restricting derivations to the single pair. A pattern with all positions free — `[:_, :_]` — has no bound positions, so `has_bound_position?/1` returns false and the transform declines:

```elixir
defp has_bound_position?(pattern) do
  Enum.any?(pattern, fn p -> p != :_ end)
end
```

An all-free goal offers no demand to exploit; the transform would generate an empty magic predicate that blocks every derivation. Falling back to semi-naive is the only sensible choice.

## Scope: Positive Recursive Programs, Single Goal, Ground Bounds

The v0.5.0 implementation deliberately limits its scope. `transform/2` applies only when all three of these hold:

1. **No negation or aggregates in any rule.** The check is whole-program, not per-rule:
   ```elixir
   defp supported_program?(%IR{rules: rules}) do
     Enum.all?(rules, fn rule ->
       not has_negation?(rule) and not has_aggregate?(rule)
     end)
   end
   ```
   Negation introduces stratification dependencies that the magic-relation stratum injection does not yet model; aggregates require grouping semantics that the rewrite does not preserve. Any rule with either causes `{:fallback, :unsupported_program}`.

2. **A single goal.** `transform/2` accepts one `{relation, pattern}`. Multi-goal demand propagation (sideways information passing across several queries) is future work.

3. **Ground bound positions.** The pattern's bound entries must be constants (`:a`, `"alice"`, `42`). Variables or computed bindings in the pattern are not supported; `to_ir_value/1` handles only integers, binaries, and atoms.

Anything outside this scope is rejected up front by the `cond` in `transform/2`, before any rewriting begins.

## Fallback: Safe by Construction

Falling back is not an error condition — it is the design's safety net. The engine treats `{:fallback, reason}` as a directive to evaluate the *original* IR with semi-naive, which always produces the correct least fixpoint. The `reason` is currently discarded by the engine; the transform's return type is the only record of *why* demand restriction was declined.

The tests make the fallback semantics explicit:

```elixir
test "falls back to semi-naive when no goal is given" do
  program = ancestor_program(@chain)
  {:ok, magic} = ExDatalog.materialize(program, strategy: :magic_sets)
  {:ok, full} = ExDatalog.materialize(program)
  assert Knowledge.get(magic, "ancestor") == Knowledge.get(full, "ancestor")
end
```

A program containing negation falls back the same way, and the result still matches full evaluation:

```elixir
{:ok, magic} =
  ExDatalog.materialize(program, strategy: :magic_sets, goal: {"childless", [:_]})

{:ok, full} = ExDatalog.materialize(program)
assert Knowledge.get(magic, "childless") == Knowledge.get(full, "childless")
```

Because the fallback path is the same engine that handles `:semi_naive`, there is no way for the `:magic_sets` strategy to produce a *wrong* answer — only a slower one.

## Correctness: Magic ≡ Semi-Naive for Goal Results

The central correctness property is that the goal-restricted result returned by magic sets equals the goal-restricted subset of the full semi-naive fixpoint:

```
magic_result(goal)  ==  filter(semi_naive_result, goal)
```

Note this is *not* equality of the full knowledge base. The magic-transformed program will derive fewer facts in non-goal relations (and even in the goal relation beyond what the goal pattern admits — that is why `Knowledge.match/3` is used to project the final result). The guarantee is scoped to the goal.

The property test in `magic_sets_property_test.exs` checks this for randomly generated graphs and sources:

```elixir
property "magic-sets result equals the semi-naive subset for the goal" do
  check all(
          edges <- list_of(edge_gen(), max_length: 10),
          source <- member_of(@nodes)
        ) do
    program = build_program(edges)

    {:ok, full} = ExDatalog.materialize(program)
    expected = MapSet.filter(Knowledge.get(full, "path"), fn {x, _y} -> x == source end)

    {:ok, magic} =
      ExDatalog.materialize(program, strategy: :magic_sets, goal: {"path", [source, :_]})

    actual = Knowledge.match(magic, "path", [source, :_])

    assert actual == expected
  end
end
```

Because the property is checked over arbitrary edge sets (including cyclic ones, disconnected ones, and empty ones), it provides strong evidence that the rewrite preserves goal semantics for the supported program class. The unit tests verify the structural shape of the transform directly — that `magic_ancestor_bf/1` exists, the seed fact `(a,)` is present, and every rewritten ancestor rule begins with the magic atom:

```elixir
assert Enum.all?(rewritten, fn r ->
         match?([{:positive, %ExDatalog.IR.Atom{relation: "magic_ancestor_bf"}} | _], r.body)
       end)
```

## Example: Ancestors of Alice vs. All Ancestors

Using the chain `parent(a,b), parent(b,c), parent(c,d), parent(d,e)`:

```elixir
@chain [{:a, :b}, {:b, :c}, {:c, :d}, {:d, :e}]
program = ancestor_program(@chain)

# Full fixpoint: every ancestor pair in the chain.
{:ok, full} = ExDatalog.materialize(program)
Knowledge.get(full, "ancestor")
#=> {(a,b), (a,c), (a,d), (a,e), (b,c), (b,d), (b,e), (c,d), (c,e), (d,e)}

# Demand-driven: only the slice rooted at :a.
{:ok, magic} =
  ExDatalog.materialize(program, strategy: :magic_sets, goal: {"ancestor", [:a, :_]})

Knowledge.match(magic, "ancestor", [:a, :_])
#=> {(a,b), (a,c), (a,d), (a,e)}
```

The semi-naive run derives ten facts; the magic-sets run derives only the four the query asked for. The magic relation `magic_ancestor_bf` carries the single seed `(a,)`, the recursive rule fires only when `X = a` propagated through `parent`, and the unrelated `b`, `c`, `d` lineages never enter the working set. On larger graphs the gap widens: demand restriction trades a linear-in-input scan for a slice whose size is bounded by the goal's actual reach.

## When to Use Magic Sets vs. Semi-Naive

Magic sets is not a universal optimisation. It pays off when the goal's reach is much smaller than the full fixpoint, and when the result is queried once and discarded. The full semi-naive materialisation is the better choice when:

- The materialised knowledge will be **reused** across many subsequent queries. The upfront cost of the full fixpoint is amortised; magic sets would re-run the transform (and the evaluation) on every query.
- The goal pattern is **all-free**, so there is no demand to exploit — the transform declines and falls back anyway.
- The program uses **negation or aggregates**, which are outside the supported scope.
- The program has **multiple goals** or needs bindings computed by side constraints (non-ground bound positions).

Magic sets earns its keep on the opposite shape: deep recursive programs, large datasets, and a single focused query whose bound positions carve a small slice out of a wide relation. In that regime it recovers the precision of top-down evaluation without abandoning the bottom-up fixpoint model that gives Datalog its termination and deterministic-output guarantees.

The feature is experimental in v0.5.0: positive recursive programs, a single goal, ground bounds, and silent fallback. It is the foundation on which sideways information passing, multi-goal demand, and negation-aware magic relations will be built in later releases.