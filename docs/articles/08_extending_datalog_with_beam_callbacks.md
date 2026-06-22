# Extending Datalog with BEAM Callbacks: Calling Elixir from Rule Bodies

Datalog's expressive power lives in joins: "find every `X` related to `Y` through `Z`." But real programs need more than relational joins — they need to call domain logic. "Is this user an adult?", "double this value", "does this email contain an `@`?" These are computations, not relations, and encoding them as base facts blows up the fact tables.

ExDatalog bridges this with **BEAM callback predicates**: ordinary Elixir functions invoked during rule evaluation, treated as first-class body literals alongside positive and negative atoms. A callback appears in a rule body, sees the current variable binding, and either filters it (boolean) or extends it (value). The engine isolates each call with a monitored process and a timeout, so a misbehaving function never kills the evaluator.

## Why Call Elixir from Datalog?

Pure Datalog computes relations from relations. Anything that isn't a stored fact must be expressed as a rule, and rules can only combine existing relations. This is the source of Datalog's guarantees — termination, determinism, decidable safety — but it also boxes the language in. A rule like:

```elixir
rule high_earner(P) do
  income(P, S)
  gt(S, 100_000)
end
```

works because `gt` is a built-in constraint. But what if the threshold depends on the person's region? Or what if "high earner" means "above the 90th percentile for their locale"? That's domain logic — it lives in Elixir, not in the fact store.

The classic escape hatch in Datalog is *built-in predicates*: a fixed set of distinguished relations (`>`, `<`, `+`, ...) with special evaluation. ExDatalog already has those — the constraint DSL — but they're hard-coded into the engine. BEAM callbacks generalize the idea: any Elixir function `Mod.fun/arity` can act as a built-in, declared per-program, evaluated against the live binding.

The trade-off is a contract: the function must be **deterministic** and **side-effect free**. The engine cannot verify this — it's the caller's responsibility — but it can, and does, isolate the call so that a violation (a crash, a hang, a throw) degrades gracefully to a filtered binding rather than a crashed evaluator.

## Boolean vs. Value Callbacks

A callback has two flavours, distinguished by its `result` field:

- **Boolean** (`result: nil`) — the function returns `true` or `false`. `true` keeps the binding; `false` (or a non-boolean, a timeout, or an exception) drops it. This is a *filter*: it never introduces new variables.
- **Value** (`result: {:var, name}`) — the function returns a value, which is bound to `name` and added to the environment. This is a *binder*: like an arithmetic constraint, it extends the binding with a new variable the rule head can project.

The two map onto different problem shapes. A boolean callback answers "does this binding pass a predicate?":

```elixir
rule adult(Name) do
  person(Name, Age)
  adult?(Age)        # boolean callback: Age >= 18
end
```

A value callback answers "compute something from this binding":

```elixir
rule doubled(X, Y) do
  num(X)
  double(X, Y)       # value callback: Y = X * 2
end
```

In the value case, `Y` is introduced by the callback and projected into the head — exactly how arithmetic constraints like `add(A, B, Z)` work. The safety rules treat the two categories symmetrically: a callback's **inputs** must be bound before the call, and its **result** (if any) is available to the head and to later constraints.

## The DSL: `predicate/5`

The Schema DSL exposes callbacks through the `predicate/5` macro, declared alongside relations:

```elixir
defmodule FamilyRules do
  use ExDatalog.Schema

  relation :person do
    field(:name, :atom)
    field(:age, :integer)
  end

  relation :adult do
    field(:name, :atom)
  end

  predicate :adult?, MyPredicates, :adult?, [:integer], :boolean

  fact person(:alice, 30)
  fact person(:bob, 10)

  rule adult(Name) do
    person(Name, Age)
    adult?(Age)
  end
end
```

The macro stores a `ExDatalog.Schema.PredicateMeta` struct — name, module, function, argument types, and return type (`:boolean` or `:value`). When the rule body is parsed, any positive atom whose relation matches a declared predicate is *rewritten* into a callback literal rather than a relational atom:

```elixir
defp resolve_positive_or_callback(%ExDatalog.Atom{relation: rel, terms: terms}, predicate_map) do
  case Map.get(predicate_map, rel) do
    nil ->
      {:positive, %ExDatalog.Atom{relation: rel, terms: Enum.map(terms, &term_from_parsed/1)}}

    %ExDatalog.Schema.PredicateMeta{} = pred ->
      build_callback_literal(pred, terms)
  end
end
```

For `:value` predicates, the **last** argument position in the rule-body call is the result variable; the rest are passed to the function:

```elixir
defp build_callback_literal(%ExDatalog.Schema.PredicateMeta{} = pred, terms) do
  arg_terms = Enum.map(terms, &term_from_parsed/1)

  case pred.return_type do
    :boolean ->
      {:callback, ExDatalog.Callback.new(pred.module, pred.function, arg_terms, nil)}

    :value ->
      {args, [result]} = Enum.split(arg_terms, length(arg_terms) - 1)
      {:callback, ExDatalog.Callback.new(pred.module, pred.function, args, result)}
  end
end
```

This split mirrors how arithmetic constraints separate inputs from the result slot: `add(A, B, Z)` takes `A` and `B` as inputs and binds `Z`. A value predicate `double(X, Y)` takes `X` as input and binds `Y`.

Argument types are currently informational — their length sets the expected arity, validated against the exported function. The runtime type of each argument is whatever the binding holds.

## The Builder API

Programs built without the DSL construct callbacks directly with `ExDatalog.Callback.new/4` and place them in the rule body as `{:callback, %Callback{}}`:

```elixir
program =
  Program.new()
  |> Program.add_relation("person", [:atom, :integer])
  |> Program.add_relation("adult", [:atom])
  |> Program.add_fact("person", [:alice, 25])
  |> Program.add_fact("person", [:bob, 12])
  |> Program.add_rule(
    Rule.new(
      Atom.new("adult", [Term.var("Name")]),
      [
        {:positive, Atom.new("person", [Term.var("Name"), Term.var("Age")])},
        {:callback, Callback.new(Predicates, :adult?, [Term.var("Age")])}
      ]
    )
  )
```

The `Callback` struct is intentionally minimal:

```elixir
@enforce_keys [:module, :function, :args]
defstruct [:module, :function, :args, :result]
```

- `module` / `function` — the Elixir function to call.
- `args` — a list of `ExDatalog.Term.t()` (variables or constants) resolved against the binding at evaluation time and passed positionally.
- `result` — `nil` for a boolean filter, or `{:var, name}` for a value-binding callback.

Two helpers verbalize the callback's variable footprint:

```elixir
@spec input_variables(t()) :: [String.t()]
def input_variables(%__MODULE__{args: args}), do: Term.variables(args)

@spec result_variable(t()) :: String.t() | nil
def result_variable(%__MODULE__{result: {:var, name}}), do: name
def result_variable(%__MODULE__{result: _}), do: nil
```

`input_variables/1` is the input to the safety checker; `result_variable/1` is what the head-safety check counts as a bound variable.

## Isolation: `spawn_monitor` and the Timeout

A callback is an arbitrary Elixir function. It might loop forever. It might raise. It might `exit`. It might link to another process that dies. The engine cannot trust it — it must isolate it.

`ExDatalog.Constraints.BeamCallback` runs every call in a freshly spawned, monitored process:

```elixir
defp safe_apply(module, function, args, timeout_ms) do
  parent = self()
  ref = make_ref()

  {pid, monitor_ref} =
    spawn_monitor(fn ->
      result =
        try do
          {:ok, apply(module, function, args)}
        rescue
          e -> {:error, e}
        catch
          kind, reason -> {:error, {kind, reason}}
        end

      send(parent, {ref, result})
    end)

  receive do
    {^ref, result} ->
      Process.demonitor(monitor_ref, [:flush])
      result

    {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
      {:error, reason}
  after
    timeout_ms ->
      Process.exit(pid, :kill)
      Process.demonitor(monitor_ref, [:flush])
      {:error, :timeout}
  end
end
```

There are three failure modes, all folded into a single `{:error, _}` → `:filter` outcome:

1. **The function returns normally** — `{:ok, value}` is sent back and the binding is kept (boolean true) or extended (value bound).
2. **The function raises or exits** — the `try/rescue/catch` inside the spawned process converts it to `{:error, e}` and the binding is filtered.
3. **The function takes too long** — the `after` clause fires, kills the process, and reports `{:error, :timeout}`.

Because the spawned process is **unlinked** and **monitored**, a crash inside it produces a `:DOWN` message — not a linked exit propagating to the evaluator. The monitor is flushed after the call so no stray `:DOWN` ever reaches the parent's mailbox.

The timeout is configurable per materialization via `:callback_timeout_ms` (default 100ms):

```elixir
{:ok, knowledge} = ExDatalog.materialize(program, callback_timeout_ms: 50)
```

The same option propagates through the `ExDatalog.Constraint.Context` carried by the evaluator, so callbacks inside rule bodies see the same deadline.

### Why `spawn_monitor`, Not `Task.async`?

`Task.async` links the task to the caller. A `raise` inside the task propagates as an exit and crashes the evaluator — the opposite of what we want. `Task.Supervisor` adds supervision overhead and a separate process tree for what is a single synchronous call. `spawn_monitor` is the lightest primitive that gives both crash isolation (no link) and death notification (the `:DOWN` message), without needing a supervisor.

### Why a Timeout, Not Cancellation?

Cancellation requires cooperative cancellation — the spawned function would have to check a flag. The engine has no control over the function's body, so cancellation is impossible in general. The timeout, by contrast, is enforced *from outside*: the evaluator stops waiting, kills the process, and moves on. The killed process may still be running its `after` cleanup, but it's disconnected from the evaluator. This trades precision for robustness: it always terminates the wait, even if the function is stuck in a NIF or a tight loop.

## Safety: Inputs Must Be Bound

A callback's arguments are resolved against the current binding. If an input variable isn't bound when the callback fires, there's nothing to pass — the call is ill-defined. ExDatalog rejects this at validation time in `Validator.Safety.check_callback_inputs/3`:

```elixir
defp check_callback_inputs(errors, %Rule{body: body}, body_bound, rule_index) do
  callbacks = for {:callback, cb} <- body, do: cb

  Enum.reduce(callbacks, errors, fn cb, acc ->
    unbound = Enum.reject(ExDatalog.Callback.input_variables(cb), fn v -> v in body_bound end)

    if unbound == [] do
      acc
    else
      [
        Error.new(
          :unbound_constraint_variable,
          %{rule_index: rule_index, variables: unbound, callback: {cb.module, cb.function}},
          "rule #{rule_index}: callback #{inspect(cb.module)}.#{cb.function} " <>
            "references unbound variable(s) #{Enum.join(unbound, ", ")}"
          | acc
        ]
      ]
    end
  end)
end
```

`body_bound` is the set of variables bound by positive body atoms. A callback may consume those, plus any arithmetic or value-callback results that precede it — but it cannot introduce a variable for itself to read. This is the same range-restriction rule that applies to constraints and negated atoms:

```elixir
# Safe: Age is bound by person/2 before adult?/1 fires
rule adult(Name) do
  person(Name, Age)
  adult?(Age)
end

# Unsafe: Z is never bound
rule bad(X) do
  person(X, Age)
  adult?(Z)        # ERROR: Z is unbound
end
```

A value callback's result variable *is* safe to use in the head, because if the rule fires at all the callback will have run:

```elixir
# Safe: Y is bound by the value callback double/1
rule doubled(X, Y) do
  num(X)
  double(X, Y)
end
```

The head-safety checker (`all_bound_variables/1`) collects callback result variables alongside arithmetic results, so a head term may reference either.

## Compile-Time Module/Function Validation

The structural validator (`Validator.check_callback/3`) checks that the named module is loaded and exports the function at the expected arity:

```elixir
defp check_callback(errors, %ExDatalog.Callback{module: m, function: f, args: args}, context) do
  arity = length(args)

  if Code.ensure_loaded?(m) and function_exported?(m, f, arity) do
    errors
  else
    [
      Error.new(
        :invalid_callback,
        Map.merge(context, %{module: m, function: f, arity: arity}),
        "#{location(context)} callback #{inspect(m)}.#{f}/#{arity} " <>
          "is not defined or not exported"
        | errors
      )
    ]
  end
end
```

`Code.ensure_loaded?/1` forces the module to be compiled (if in the same VM) and confirms it exists; `function_exported?/3` checks the function clause. The check runs as part of `Validator.validate/1`, which is called from `ExDatalog.materialize/2`. A program that references `DoesNotExist.foo/1` is rejected before evaluation begins:

```elixir
assert {:error, errors} = ExDatalog.materialize(program)
assert Enum.any?(errors, fn e -> e.kind == :invalid_callback end)
```

A callback that passes the arity check but misbehaves at runtime (raises, times out) is *not* a validation error — it's handled by the isolation machinery and filtered out of the result.

## The Evaluation Pipeline

Callbacks slot into a fixed position in the per-binding pipeline. In `Engine.Evaluator.finish_bindings/4`, each binding produced by the positive-body join passes through four stages in order:

```elixir
defp finish_bindings(bindings, rule, full, ctx) do
  bindings = apply_constraints(rule.body, bindings, ctx)
  bindings = apply_callbacks(rule.body, bindings, ctx)
  bindings = apply_negation(rule.body, bindings, full)

  case bindings do
    [] -> []
    _ -> Enum.map(bindings, &Join.project(rule.head, &1))
  end
end
```

1. **Constraints** — comparisons filter; arithmetic extends the binding.
2. **Callbacks** — boolean callbacks filter; value callbacks extend the binding.
3. **Negation** — surviving bindings are checked against the fully-materialized lower-stratum relations.
4. **Projection** — the head is projected from each surviving binding.

The ordering matters. Constraints run first because they're cheap and pure — a `gt` comparison is faster and more reliable than an arbitrary Elixir function, so filtering with `gt` *before* calling a callback avoids wasted calls. Callbacks run before negation because callbacks may bind the result variables that negated atoms reference:

```elixir
rule verified_adult(Name) do
  person(Name, Age)
  adult?(Age)
  id_for(Name, Id)       # value callback binds Id
  not_ banned(Id)        # negation uses Id
end
```

If callbacks ran after negation, `Id` wouldn't be bound when `not_ banned(Id)` was checked, and the negated atom would either fail safety or match incorrectly.

Within the callback stage, multiple callbacks in the same rule are chained in listed order through `apply_callback_chain/3`:

```elixir
defp apply_callback_chain(callbacks, binding, opts) do
  Enum.reduce_while(callbacks, [binding], fn cb, [b] ->
    step_callback(BeamCallback.apply_callback(cb, b, opts))
  end)
end

defp step_callback({:ok, new_b}), do: {:cont, [new_b]}
defp step_callback(:filter), do: {:halt, []}
```

A `:filter` short-circuits the rest of the chain — the binding is dropped, no later callback in that rule fires. A successful value callback extends the binding and the next callback sees the new variable.

## The Contract: Deterministic and Side-Effect Free

The engine enforces isolation (timeout, exception handling, monitored processes). It cannot enforce purity. A callback that:

- reads the current time,
- queries a database,
- sends a message,
- mutates a process dictionary,
- depends on application state,

will produce results that depend on *when* the rule fires, not just *what* the binding contains. In a semi-naive evaluator the same rule fires repeatedly across fixpoint iterations; a non-deterministic callback can break monotonicity, violate the fixpoint, and produce different results across runs.

The contract — stated in `ExDatalog.Callback`'s moduledoc — is:

> A callback **must** be:
>
> - **Deterministic** — the same arguments always produce the same result.
> - **Side-effect free** — no I/O, mutation, or messaging.

These are caller contracts, not engine-enforced. The engine's isolation layer is the safety net for *accidents* — a stack overflow, a misbehaving dependency — not for *intent*. A program that deliberately calls `DateTime.utc_now/0` from a callback will run; its result will simply be unreliable.

## Limitations and Design Choices

BEAM callbacks are the most permissive feature in ExDatalog, and several limits reflect that:

- **No type-level enforcement of arguments.** `arg_types` in `predicate/5` is informational. The validator checks the function exists with the right arity, not that the binding's runtime values match the declared types. Type checking would require either a runtime check (slow, and Elixir doesn't have value types) or a static analysis pass over the program — both out of scope for v0.4.

- **No cancellation.** As discussed above, the timeout is a wait-side deadline, not a cooperative cancel. A callback stuck in a NIF cannot be interrupted.

- **No parallelism.** Callbacks in a single rule run sequentially, in listed order, threaded through `apply_callback_chain`. Parallel evaluation would break ordering-dependent value callbacks (`a(X) -> double(X, Y) -> next(Y, Z)` is sequential by construction).

- **No memoization.** The same callback called with the same arguments in two different iterations of a fixpoint loop runs twice. A deterministic, side-effect-free function gives the same answer each time, but the cost is paid again. Memoization would require a per-program cache with eviction, which complicates the stateless evaluation model.

- **One result variable.** A value callback binds exactly one variable — the last argument position in the DSL call. A function returning `{a, b}` cannot bind two variables directly; the rule must follow up with a constraint or a second callback to decompose the tuple.

- **Callbacks are not relations.** They participate in the safety checks and the evaluation pipeline, but they do not appear in the dependency graph. A callback cannot be the head of a rule, cannot be negated, and cannot be recursive. They are leaves in the stratification order — by construction, since their "relations" are Elixir functions, not Datalog predicates.

These limits keep the feature small and the guarantees intact. A callback that can be statically typed, cancelled, parallelised, and memoized is a different abstraction — closer to a foreign-function interface than to a Datalog literal. ExDatalog's callbacks stay close to the spirit of built-in predicates: an open set of pure functions, grafted onto the engine with a thin isolation layer, paying their way with the work they save in fact-table size.

## What's Coming in v0.5.0

- **Aggregates** — `count`, `sum`, `min`, and `max` over a relation, stratified above their inputs. Aggregates share the value-binding shape with value callbacks (a result variable introduced into the binding) but are evaluated by group-and-reduce over the materialized relation rather than per-binding.
- **Magic sets / demand-driven evaluation** — goal-directed evaluation that computes only facts relevant to a query, instead of the full fixpoint.
- **Static callback purity analysis** — an optional lint pass that flags callbacks whose module is known to perform I/O (e.g. modules implementing `GenServer` behaviour), to surface contract violations before runtime.

These features will expand what's expressible while preserving Datalog's guarantees: termination, deterministic output, and compile-time validation.