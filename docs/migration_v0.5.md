# Migrating from v0.4 to v0.5

ExDatalog v0.5.0 adds aggregate constraints, BEAM callback predicates,
magic-sets program transformation, and a query planner. All v0.4.1 code works
unchanged — the new features are opt-in extensions to the existing DSL and
builder API.

This guide covers each new feature and the few deprecations.

## Backward Compatibility

Every program that compiles and runs under v0.4.1 continues to do so under
v0.5.0. No APIs were removed; no default behaviours changed. The only
breaking-ish change is that `agg(...)` in DSL rule bodies now raises with a
redirect message instead of a generic error (see below).

## Aggregates

v0.5.0 introduces four aggregate constraint operations: `count`, `sum`, `min`,
and `max`. Unlike comparison or arithmetic constraints, aggregates operate over
the full set of bindings for a rule, grouped by the non-aggregated variables.

### DSL Syntax

Aggregates appear in the rule body, not the head. The result variable is then
used in the head:

```elixir
defmodule HR do
  use ExDatalog.Schema

  relation :employee do
    field :name, :atom
    field :dept, :atom
    field :salary, :integer
  end

  relation :dept_size do
    field :dept, :atom
    field :count, :integer
  end

  fact employee(:alice, :eng, 120)
  fact employee(:bob, :eng, 95)
  fact employee(:carol, :ops, 80)

  rule dept_size(Dept, N) do
    employee(Name, Dept, Salary)
    count(Name, N)
  end
end

{:ok, knowledge} = HR.materialize()
# knowledge contains dept_size(:eng, 2), dept_size(:ops, 1)
```

Supported aggregate operations in the DSL: `count/2`, `sum/2`, `min/2`,
`max/2`. The first argument is the input variable; the second is the result
variable that the engine binds after group-and-reduce.

### Builder API

Use `Constraint.from_tuple/1` with an aggregate tuple:

```elixir
alias ExDatalog.{Program, Rule, Atom, Term, Constraint}

program =
  Program.new()
  |> Program.add_relation("employee", [:atom, :atom, :integer])
  |> Program.add_relation("dept_size", [:atom, :integer])
  |> Program.add_fact("employee", [:alice, :eng, 120])
  |> Program.add_fact("employee", [:bob, :eng, 95])

aggregate_constraint = Constraint.from_tuple({:count, Term.var("Name"), Term.var("N")})

program =
  Program.add_rule(program,
    Rule.new(
      Atom.new("dept_size", [Term.var("Dept"), Term.var("N")]),
      [{:positive, Atom.new("employee", [Term.var("Name"), Term.var("Dept"), Term.var("Salary")])}],
      [aggregate_constraint]
    )
  )
```

### Constraint Table

Aggregate constraints use the `%Constraint{op: :count | :sum | :min | :max,
left: input_term, right: nil, result: {:var, name}}` shape. The `right` field
is always `nil` for aggregates; the grouping key is inferred from the rule's
non-aggregated variables.

| Field | Value |
|-------|-------|
| `op` | `:count`, `:sum`, `:min`, `:max` |
| `left` | input term (the variable to aggregate) |
| `right` | `nil` |
| `result` | `{:var, name}` — the output variable |

## BEAM Callbacks

BEAM callbacks let rule bodies call deterministic, side-effect-free Elixir
functions as predicates. The engine isolates callbacks with a configurable
timeout (default 100 ms) and treats exceptions/timeouts as filtered bindings.

### `predicate/5` Macro

Declare callbacks in the DSL module using `predicate/5`:

```elixir
defmodule MyRules do
  use ExDatalog.Schema

  relation :person do
    field :name, :atom
    field :age, :integer
  end

  relation :senior do
    field :name, :atom
  end

  predicate :senior?, MyRules, :senior?, [:integer], :boolean

  fact person(:alice, 70)
  fact person(:bob, 25)

  rule senior(Name) do
    person(Name, Age)
    senior?(Age)
  end

  def senior?(age), do: age >= 65
end

{:ok, knowledge} = MyRules.materialize()
```

Arguments:

- `name` — predicate name used in rule bodies (e.g. `senior?`).
- `module` / `function` — the Elixir module and function to call.
- `arg_types` — declared argument types (informational; length sets the
  callback arity).
- `return_type` — `:boolean` (filter) or `:value` (binds last argument as
  result).

### Value-Returning Callbacks

For `:value` predicates, the **last** argument in the rule-body call is the
result variable; remaining arguments are passed to the function:

```elixir
defmodule ScoreRules do
  use ExDatalog.Schema

  relation :player do
    field :name, :atom
    field :raw, :integer
  end

  relation :ranked do
    field :name, :atom
    field :score, :integer
  end

  predicate :compute_score, ScoreRules, :compute_score, [:integer], :value

  fact player(:alice, 80)
  fact player(:bob, 40)

  rule ranked(Name, Score) do
    player(Name, Raw)
    compute_score(Raw, Score)
  end

  def compute_score(raw), do: div(raw * 3, 2)
end
```

### Builder API: `Callback.new/4`

```elixir
alias ExDatalog.{Callback, Term}

# Boolean filter callback
cb = Callback.new(MyMod, :adult?, [Term.var("Age")])
#=> %Callback{module: MyMod, function: :adult?, args: [{:var, "Age"}], result: nil}

# Value-returning callback
cb = Callback.new(MyMod, :score, [Term.var("X")], Term.var("S"))
#=> %Callback{module: MyMod, function: :score, args: [{:var, "X"}], result: {:var, "S"}}
```

Add a callback to a rule's body as `{:callback, %Callback{}}`:

```elixir
rule =
  Rule.new(
    Atom.new("senior", [Term.var("Name")]),
    [
      {:positive, Atom.new("person", [Term.var("Name"), Term.var("Age")])},
      {:callback, Callback.new(MyMod, :senior?, [Term.var("Age")])}
    ]
  )
```

### Safety Contract

Callbacks **must** be deterministic and side-effect free. The engine enforces
only timeout and exception isolation — determinism and purity are caller
contracts.

## Magic Sets

Magic-sets is a program transformation for demand-driven (goal-directed)
evaluation. Instead of computing the full least fixpoint, it rewrites the
program so that only facts relevant to a query goal are derived.

### `materialize/2` Options

Pass `strategy: :magic_sets` and `goal: {relation, pattern}` to
`materialize/2`:

```elixir
{:ok, knowledge} =
  ExDatalog.materialize(program,
    strategy: :magic_sets,
    goal: {"path", [:alice, :_]}
  )
```

The same options work from the DSL:

```elixir
{:ok, knowledge} =
  MySchema.materialize(
    strategy: :magic_sets,
    goal: {"path", [:alice, :_]}
  )
```

When `strategy: :magic_sets` is specified without a `:goal`, the engine falls
back to full semi-naive evaluation. When the program is outside the supported
scope (negation, aggregates), the transformation returns `{:fallback, reason}`
and the engine also falls back silently.

### Scope (Experimental)

- Positive recursive programs only.
- A single goal.
- Ground (constant) bound positions.

Programs outside this scope always fall back to full semi-naive evaluation,
never producing incorrect results.

## Planner

The planner sits between compiled IR and the evaluation engine. It produces an
`ExDatalog.Planner.Plan` describing the chosen strategy, planned strata, joins,
and predicates.

### `plan/2`

```elixir
alias ExDatalog.{Program, Rule, Atom, Term, Compiler, Planner}

{:ok, ir} =
  Program.new()
  |> Program.add_relation("edge", [:atom, :atom])
  |> Program.add_relation("path", [:atom, :atom])
  |> Program.add_rule(
    Rule.new(
      Atom.new("path", [Term.var("X"), Term.var("Y")]),
      [{:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}]
    )
  )
  |> Compiler.compile()

{:ok, plan} = Planner.plan(ir)
plan.strategy   #=> :semi_naive
plan.joins      #=> [%Join{relation: "edge", ...}]
plan.predicates #=> []

{:ok, plan} = Planner.plan(ir, strategy: :magic_sets, goal: {"path", [:alice, :_]})
plan.strategy   #=> :magic_sets
```

### `explain_plan/1,2`

Returns a human-readable description of the plan:

```elixir
Planner.explain_plan(program)
#=> "Strategy: semi_naive\n  Stratum 0: 1 rule(s), relations: edge, path\nJoins: 1\nPredicates: 0"

Planner.explain_plan(program, strategy: :magic_sets, goal: {"path", [:alice, :_]})
#=> "Strategy: magic_sets\n  Stratum 0: 1 rule(s), relations: magic_path_bf, edge, path\nJoins: 2\nPredicates: 0"
```

`explain_plan/1` validates and compiles the program first; returns an error
string if compilation fails.

### Telemetry Events

`plan/2` emits the following telemetry events:

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:ex_datalog, :planner, :start]` | `%{system_time: ...}` | `%{relation_count: ..., rule_count: ...}` |
| `[:ex_datalog, :planner, :stop]` | `%{duration: ...}` | `%{relation_count: ..., rule_count: ..., strategy: ...}` |
| `[:ex_datalog, :planner, :exception]` | `%{duration: ...}` | `%{relation_count: ..., rule_count: ..., kind: ..., reason: ...}` |

## New Capabilities Fields

`ExDatalog.Capabilities` has two new boolean fields:

| Field | Default | Description |
|-------|---------|-------------|
| `aggregate_constraints` | `true` | Supports aggregate constraints (count/sum/min/max) |
| `beam_callbacks` | `true` | Supports BEAM callback predicates |

Both participate in `merge/2` (AND semantics) and `satisfies?/2`:

```elixir
caps = %ExDatalog.Capabilities{aggregate_constraints: true, beam_callbacks: false}
ExDatalog.Capabilities.satisfies?(caps, aggregate_constraints: true)
#=> true
ExDatalog.Capabilities.satisfies?(caps, beam_callbacks: true)
#=> false
```

## Deprecated / Changed

### `agg(...)` raises with a redirect

Using `agg(...)` in a DSL rule head or body now raises
`ExDatalog.DSL.CompileError` with a redirect message:

```
rule dept_size(D, agg(:count, E)) do
  employee(E, D)
end
#=> ** (ExDatalog.DSL.CompileError) use count/sum/min/max for aggregates (e.g. `count(X, N)`)
```

Previously, `agg(...)` raised a generic "unsupported term" error. The new
message directs you to the correct aggregate syntax. Use `count/2`, `sum/2`,
`min/2`, or `max/2` in the rule body instead.

## New Dependencies

- `benchee ~> 1.3` — dev-only, not included in production builds. Used for
  benchmarking the planner and magic-sets transformations.
