# Query Planning in ExDatalog: The Seam Between IR and Engine

Datalog evaluation looks direct — apply the rules, accumulate facts, stop at a fixpoint. But between the validated `ExDatalog.IR` and the semi-naive engine sits a small planner whose job is to describe *how* a program will run before it runs. ExDatalog's planner is thin by design in v0.5.0, but it is the structure future optimizations hang from: join ordering, cost-based selection, and goal-directed evaluation all plug in here.

## Why Datalog Needs a Planner

The IR describes *what* a program means: relations, rules, strata, safety-validated bodies. The engine describes *how* it runs: nested-loop joins, delta tracking, monotonic fixpoint iteration. Between the two, several decisions need a home:

- which evaluation **strategy** applies (semi-naive bottom-up vs. goal-directed magic sets);
- how each rule is **stratified** (already computed by the validator, but the engine wants the resolved `IR.Rule` structs grouped by stratum);
- which **joins** the engine will perform — one per positive body atom — and in what *position*, so the delta slot maps cleanly during semi-naive iteration;
- which **predicates** (constraints, aggregates, callbacks) must run, classified by kind so the engine can dispatch them uniformly;
- where **telemetry** fires so observers can profile planning without instrumenting every rule.

Putting these decisions in their own struct means the engine stays a pure consumer of the plan, and an optimizer can swap plans without touching the engine. That separation is what makes the planner the right seam for future work.

## The Four Planner Structs

The plan is assembled from four small structs. Each is descriptive — it explains what the engine will do rather than dictating bytecode.

### `ExDatalog.Planner.Plan`

The top-level plan records the chosen `strategy`, the planned `strata`, the flat list of `joins`, the flat list of `predicates`, and a small `metadata` map (currently carrying the goal, if any):

```elixir
@enforce_keys [:strategy, :strata]
defstruct [:strategy, strata: [], joins: [], predicates: [], metadata: %{}]

@type strategy :: :semi_naive | :magic_sets
```

The plan is descriptive by construction. Aggregate and callback predicates do not get their own fields — they appear in `predicates` with `kind: :aggregate` / `kind: :callback`, so adding new predicate categories later does not change the struct.

### `ExDatalog.Planner.Stratum`

A planned stratum wraps the IR stratum into a form the engine wants: the actual `IR.Rule` structs, not just their IDs, alongside the relations that belong to that stratum:

```elixir
@enforce_keys [:index, :rules, :relations]
defstruct [:index, :rules, :relations]
```

The planner builds these by filtering rules whose `stratum` field matches each IR stratum's `index`:

```elixir
defp build_strata(%IR{strata: strata, rules: rules}) do
  Enum.map(strata, fn %IR.Stratum{index: idx, relations: rels} ->
    stratum_rules = Enum.filter(rules, fn r -> r.stratum == idx end)
    %Stratum{index: idx, rules: stratum_rules, relations: rels}
  end)
end
```

This is where the validator's stratification work flows into the engine: each `Stratum` runs to a local fixpoint before the next begins, guaranteeing that negated relations are complete before any rule that negates them fires.

### `ExDatalog.Planner.Join`

A join is one positive body atom position within a rule. `position` is the 0-based index of the atom within the rule's positive body; `delta_position` indicates the semi-naive delta slot it maps to; `strategy` records how the join is executed, defaulting to `:nested_loop`:

```elixir
@enforce_keys [:relation, :position]
defstruct [:relation, :position, delta_position: nil, strategy: :nested_loop]

@type strategy :: :nested_loop | :indexed
```

The planner emits one join per positive body atom across all rules. For the classic transitive-closure program (`path(X,Y) :- edge(X,Y)` plus `path(X,Z) :- edge(X,Y), path(Y,Z)`), that's three joins — one for the first rule's body and two for the second rule's two positive atoms:

```elixir
defp build_joins(%IR{rules: rules}) do
  Enum.flat_map(rules, fn rule ->
    rule.body
    |> Enum.filter(&match?({:positive, _}, &1))
    |> Enum.with_index()
    |> Enum.map(fn {{:positive, %IR.Atom{relation: rel}}, position} ->
      %Join{relation: rel, position: position, delta_position: position}
    end)
  end)
end
```

Negative atoms and constraints are deliberately excluded — they filter, they don't join. The `delta_position` mirrors `position` because, in the current engine, every positive atom of a recursive rule participates in the delta; future join reorderings will reassign this field.

### `ExDatalog.Planner.Predicate`

A predicate is any non-relational body element: a constraint, an aggregate, or a callback. `kind` groups it into one of the evaluation categories; `op` is the specific operator:

```elixir
@enforce_keys [:kind, :op]
defstruct [:kind, :op, metadata: %{}]

@type kind ::
        :comparison | :arithmetic | :type | :string |
        :membership | :aggregate | :callback
```

Classification leans on `ExDatalog.Constraint`'s operator predicates:

```elixir
defp constraint_kind(op) do
  cond do
    Constraint.comparison_op?(op) -> :comparison
    Constraint.arithmetic_op?(op) -> :arithmetic
    Constraint.type_op?(op)       -> :type
    Constraint.string_op?(op)     -> :string
    Constraint.membership_op?(op) -> :membership
    Constraint.aggregate_op?(op)  -> :aggregate
    true                          -> :comparison
  end
end
```

This classification matters for the engine: comparison, type, string, and membership predicates filter bindings, while arithmetic predicates *extend* the binding environment with their result variable. The plan records that distinction once, so the engine dispatches on `kind` rather than re-deriving it per iteration.

## `plan/2` and `explain_plan/1,2`

The two public entry points cover the two use cases: programmatic planning for the engine, and human-readable planning for debugging.

### `plan/2`

`plan/2` takes a compiled `IR` and returns `{:ok, %Plan{}}`. It accepts two options:

- `:strategy` — `:semi_naive` (the default) or `:magic_sets`;
- `:goal` — a `{relation, pattern}` tuple used with `:magic_sets` (e.g. `{"path", [:a, :_]}` for goal-directed evaluation).

```elixir
iex> alias ExDatalog.{Program, Rule, Atom, Term, Compiler, Planner}
iex> {:ok, ir} =
...>   Program.new()
...>   |> Program.add_relation("edge", [:atom, :atom])
...>   |> Program.add_relation("path", [:atom, :atom])
...>   |> Program.add_rule(
...>     Rule.new(
...>       Atom.new("path", [Term.var("X"), Term.var("Y")]),
...>       [{:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}]
...>     )
...>   )
...>   |> Compiler.compile()
iex> {:ok, plan} = Planner.plan(ir)
iex> plan.strategy
:semi_naive
iex> length(plan.joins)
1
```

The magic-sets strategy is selected by simply passing the option:

```elixir
{:ok, plan} = Planner.plan(ir, strategy: :magic_sets, goal: {"path", [:a, :_]})
plan.strategy            #=> :magic_sets
plan.metadata.goal       #=> {"path", [:a, :_]}
```

### `explain_plan/1,2`

`explain_plan/1,2` is the debugging surface. It accepts a `Program` rather than an IR, validates and compiles it, plans the result, and renders a human-readable summary:

```elixir
iex> Planner.explain_plan(program) =~ "Strategy: semi_naive"
true
```

The output is a small multi-line string. For the transitive-closure program with one rule it reads:

```
Strategy: semi_naive
  Stratum 0: 1 rule(s), relations: edge, path
Joins: 1
Predicates: 0
```

Constraints surface as a parenthesized list of operators:

```
Predicates: 1 (gt)
```

The formatter is straightforward — it joins the header, the per-stratum lines, and the join/predicate counts with `\n`:

```elixir
defp format_plan(%Plan{} = plan) do
  header = "Strategy: #{plan.strategy}"

  strata_lines =
    Enum.map(plan.strata, fn s ->
      "  Stratum #{s.index}: #{length(s.rules)} rule(s), relations: #{Enum.join(s.relations, ", ")}"
    end)

  join_line = "Joins: #{length(plan.joins)}"

  pred_line =
    "Predicates: #{length(plan.predicates)}" <>
      case plan.predicates do
        [] -> ""
        preds -> " (#{Enum.map_join(preds, ", ", & &1.op)})"
      end

  Enum.join([header | strata_lines] ++ [join_line, pred_line], "\n")
end
```

If the program fails to compile — say, an unsafe rule where `Z` is unbound — `explain_plan` returns an error string rather than raising:

```elixir
iex> Planner.explain_plan(bad_program) =~ "compilation failed"
true
```

This makes `explain_plan/1,2` cheap to wire into a REPL or a `mix` task without having to handle exception flows.

## Strategy Selection

Strategy is recorded, not yet *executed* differently. In v0.5.0 the planner is honest about this in its module doc:

> When `:magic_sets` is requested, a `:goal` option (`{relation, pattern}`) should be supplied; otherwise the planner records the strategy but the engine falls back to semi-naive.

So selecting `:magic_sets` changes the plan's `strategy` field and stashes the goal in `metadata`, but the existing `Engine.Naive` still runs semi-naive bottom-up. The point of recording the strategy now is that the *shape* of the plan changes — future magic-sets rewriting will introduce magic predicates and adornment joins while keeping the same `Plan`/`Stratum`/`Join`/`Predicate` structs. Selecting the strategy is a one-line change at the call site:

```elixir
Planner.plan(ir)                                       # :semi_naive
Planner.plan(ir, strategy: :magic_sets, goal: {"path", [:a, :_]})
```

This means the planner is the right hook today for tooling that wants to *predict* which strategy will run, even if the engine hasn't yet caught up.

## Telemetry Events

`plan/2` emits one set of telemetry events per call — never per rule — so observers see the planning cost as a whole:

| Event | Measurements | Metadata |
|---|---|---|
| `[:ex_datalog, :planner, :start]` | `%{system_time: System.system_time()}` | `%{relation_count, rule_count}` |
| `[:ex_datalog, :planner, :stop]` | `%{duration: monotonic_diff}` | metadata + `:strategy` |
| `[:ex_datalog, :planner, :exception]` | `%{duration: monotonic_diff}` | metadata + `%{kind: :error, reason: exception}` |

The implementation wraps the planning body in `try/rescue` so any failure still emits the `:exception` event before re-raising:

```elixir
:telemetry.execute([:ex_datalog, :planner, :start], %{system_time: System.system_time()}, metadata)
start = System.monotonic_time()

try do
  plan = %Plan{strategy: strategy, strata: build_strata(ir), joins: build_joins(ir),
               predicates: build_predicates(ir), metadata: %{goal: goal}}
  :telemetry.execute([:ex_datalog, :planner, :stop], %{duration: System.monotonic_time() - start},
                      Map.put(metadata, :strategy, strategy))
  {:ok, plan}
rescue
  e ->
    :telemetry.execute([:ex_datalog, :planner, :exception], %{duration: System.monotonic_time() - start},
                       Map.merge(metadata, %{kind: :error, reason: e}))
    reraise e, __STACKTRACE__
end
```

Attach with `:telemetry.attach/4` to react to slow planning, or use `:telemetry.span/3` wrappers in higher-level tooling that wants a single composite event. The per-call (rather than per-rule) granularity keeps planning telemetry cheap: a thousand-rule program still emits exactly three events on failure.

## Where the Planner Sits in the Pipeline

ExDatalog's evaluation pipeline is now.Compiler → Validator → Planner → Engine:

```
Program (DSL)
   │  Program.compile/1 or ExDatalog.compile/1
   ▼
IR  (relations, facts, rules, strata, metadata)
   │  ExDatalog.Planner.plan/2
   ▼
Plan (strategy, strata, joins, predicates, metadata)
   │  Engine.Naive.eval_plan/2 (or future engine)
   ▼
Knowledge  (materialized relations: MapSet of tuples)
   │  Schema.query/2, find/where
   ▼
result
```

The validator runs *before* the planner — that's why `plan/2` accepts the already-validated IR, and why `explain_plan/2`'s "compilation failed" path goes through `ExDatalog.compile/1` (which bundles validation) rather than re-validating inside the planner. The planner is a pure consumer of validated IR.

The engine is the next consumer of the plan. Each `Stratum` in the plan corresponds to one fixpoint loop in the engine; each `Join` corresponds to one nested-loop scan; each `Predicate` corresponds to one filter or binding extension. Because the plan is descriptive, the engine doesn't *need* it to function — it can read the IR directly — but using the plan means future optimizations (join reordering, indexed joins, magic-sets rewriting) can land in the planner and immediately benefit every engine that consumes plans.

## Practical Notes

- **The plan is cheap to build.** A few `Enum.flat_map` passes over the rules; no allocation per fact. There's no reason to skip it in production.
- **Use `explain_plan/1` for debugging.** It compiles for you and returns a string you can `IO.puts` without touching data structures.
- **Use `plan/2` for tooling.** It gives you the structs you can serialize, diff, or compare across program versions.
- **Attach telemetry once.** `[:ex_datalog, :planner, :stop]` carries the `:strategy` and the rules/relations counts — enough to build a dashboard without parsing the plan.
- **Don't expect magic sets to accelerate execution yet.** In v0.5.0 the strategy is recorded; the engine still runs semi-naive. The seam is in place so a future release can hook in goal-directed rewriting without changing call sites.

The planner is small on purpose. The cost of getting the seam right now — descriptive structs, honest strategy selection, telemetry from day one — is low, and it pays back the moment a real optimizer needs somewhere to live.