# Aggregates in Datalog: Group, Reduce, Stratify

Pure Datalog derives facts by recursive joining: if `ancestor(X,Y)` holds whenever `parent(X,Y)` or `parent(X,Z)` and `ancestor(Z,Y)`, every answer falls out of the fixpoint. But many real questions are not about *what* is true — they are about *how many* or *how much*. "How many employees per department?" "What is the largest score in each group?" "What is the total salary paid to each team?"

These are aggregate queries. Classical Datalog has no aggregates: the least-fixpoint semantics is defined over sets of facts, and adding "count" looks innocuous but breaks monotonicity — later derivations can change a count that an earlier rule already consumed. ExDatalog introduces aggregates as a constrained first-class feature: four integer-only operators, one aggregate per rule, no recursion through the aggregate, and a stratification pass that forces the aggregate's head relation to live strictly above every relation that feeds it.

## Why Aggregates Are Not Just Another Constraint

Comparison and arithmetic constraints are *per-binding*. Given a binding `%{"X" => 10, "Y" => 3}`, evaluating `gt(X, 5)` or `add(X, Y, Z)` is a local, stateless operation — the answer depends only on that one binding. The engine can fold them into the per-row constraint pipeline (`ConstraintEval.apply/3`) without caring about other bindings.

Aggregates break that model. `count(E, N)` needs to see *all* employees in a department before it can pick `N`. There is no single binding that yields 2 — the value 2 only exists relative to a *group* of bindings. That is why `ExDatalog.Constraints.Aggregate.evaluate/3` does not compute anything:

```elixir
@impl ExDatalog.Constraint
def evaluate(_constraint, _binding, _context) do
  raise "aggregate constraints are not evaluated per-binding; " <>
          "use ExDatalog.Engine.Evaluator group-and-reduce path"
end
```

The behaviour callback exists only so the aggregate module fits the same dispatch table as comparisons and arithmetic. Real evaluation happens later, in the engine, after the per-binding pipeline is done. This split is the central design decision behind aggregates in ExDatalog: a constraint declares the *intent* ("count `E` into `N`"), and the engine decides *when* to honor it.

## The Four Operators

ExDatalog ships four aggregate operators. They are integer-only — there is no `avg` yet — and live in the same `@aggregate_ops` list as the rest of the constraint categories:

```elixir
@aggregate_ops [:count, :sum, :min, :max]
```

| Constructor | op | Semantics over a group's `input` values |
|---|---|---|
| `Constraint.count(input, result)` | `:count` | `length(values)` — group size |
| `Constraint.sum(input, result)` | `:sum` | `Enum.sum(values)` — integer total |
| `Constraint.min(input, result)` | `:min` | `Enum.min(values)` — smallest |
| `Constraint.max(input, result)` | `:max` | `Enum.max(values)` — largest |

The reducer itself is a four-clause function in `ExDatalog.Constraints.Aggregate`:

```elixir
defp compute(:count, values), do: length(values)
defp compute(:sum, values), do: Enum.sum(values)
defp compute(:min, values), do: Enum.min(values)
defp compute(:max, values), do: Enum.max(values)
```

`count` works on any group; `count` of employees is the size of the group regardless of the input variable's type. `sum`, `min`, and `max` require integer inputs. The plan is to enforce this at build time and guard at runtime; today an input list containing non-integers would surface as an Elixir runtime error from `Enum.sum/1` or `Enum.min/1`. Because aggregates are stratified above their inputs (see below), the input list is fully materialized and final before the reducer runs, so a runtime crash during reduction is a property of the data, not of evaluation order.

## The DSL Syntax

In the Schema DSL, aggregates appear in rule *bodies*, never in heads. The DSL expands `count(X, N)` in a body position into a `%Constraint{op: :count, left: {:var, "X"}, right: nil, result: {:var, "N"}}`. A typical rule:

```elixir
rule dept_count(D, N) do
  emp(E, D)
  count(E, N)
end
```

Two compile-time safeguards prevent misuse:

1. Aggregates are rejected in the rule head. `rule dept_count(D, count(E))` raises:

   ```
   ** (ExDatalog.DSL.CompileError) aggregate :count/2 cannot appear in a rule head
   or as a term; place it in the rule body (e.g. `count(X, Result)`) and use
   Result in the head
   ```

2. The legacy `agg(:count, X)` form is rejected with a hint to use the named operator:

   ```
   ** (ExDatalog.DSL.CompileError) use count/sum/min/max for aggregates
   (e.g. `count(X, N)`)
   ```

Both checks live in `parse_term/1` and `parse_body_call/1`. The body form is generated from the same `[:count, :sum, :min, :max]` list used by the builder, so the DSL and the programmatic API cannot drift:

```elixir
Enum.each(aggregate_ops, fn op ->
  defp parse_body_call({unquote(op), _, [input, result]}) do
    {:constraint, build_aggregate(unquote(op), input, result)}
  end
end)
```

The result variable (`N` in `count(E, N)`) is the one that appears in the rule head. The input variable (`E`) must be bound by a positive body atom. Everything else about the rule looks ordinary — and that is the point: aggregates are *constraints* from the DSL's perspective, even though the engine treats them specially.

## The Builder API

Programs that bypass the DSL construct aggregate constraints directly. `ExDatalog.Constraint` exposes one constructor per operator:

```elixir
iex> ExDatalog.Constraint.count({:var, "Emp"}, {:var, "N"})
%ExDatalog.Constraint{op: :count, left: {:var, "Emp"}, right: nil, result: {:var, "N"}}

iex> ExDatalog.Constraint.sum({:var, "Amount"}, {:var, "Total"})
%ExDatalog.Constraint{op: :sum, left: {:var, "Amount"}, right: nil, result: {:var, "Total"}}

iex> ExDatalog.Constraint.min({:var, "Score"}, {:var, "Lowest"})
%ExDatalog.Constraint{op: :min, left: {:var, "Score"}, right: nil, result: {:var, "Lowest"}}

iex> ExDatalog.Constraint.max({:var, "Score"}, {:var, "Highest"})
%ExDatalog.Constraint{op: :max, left: {:var, "Score"}, right: nil, result: {:var, "Highest"}}
```

All four constructors route through the private `aggregate/3` helper, which is what distinguishes an aggregate structurally from a comparison: `right` is always `nil`, and `result` is always a `{:var, name}` tuple. The validity check enforces this:

```elixir
defp valid_right?(op, nil) when op in @type_ops or op in @aggregate_ops, do: true

defp valid_result?(op, {:var, name}) when op in @arithmetic_ops or op in @aggregate_ops,
  do: is_binary(name) and byte_size(name) > 0
```

The same shape is reachable through `Constraint.from_tuple/1`, which is what the DSL uses internally and what tests use to check the wire format:

```elixir
iex> ExDatalog.Constraint.from_tuple({:count, {:var, "X"}, {:var, "N"}})
%ExDatalog.Constraint{op: :count, left: {:var, "X"}, right: nil, result: {:var, "N"}}

iex> ExDatalog.Constraint.from_tuple({:sum, :A, :T})
%ExDatalog.Constraint{op: :sum, left: {:var, "A"}, right: nil, result: {:var, "T"}}
```

`from_tuple/1` reuses `Term.from/1`, so the Prolog convention applies: uppercase atoms become variables, lowercase atoms and other values become constants.

A full aggregate rule built by hand — the same rule the DSL `dept_count` example compiles to — looks like:

```elixir
Rule.new(
  Atom.new("dept_count", [Term.var("D"), Term.var("N")]),
  [{:positive, Atom.new("emp", [Term.var("E"), Term.var("D")])}],
  [Constraint.count(Term.var("E"), Term.var("N"))]
)
```

The aggregate lives in the `constraints` list alongside any comparisons; the engine distinguishes it by `op` and routes it to the group-and-reduce path.

## Grouping Semantics

The hard question for any aggregate is "group by what?" ExDatalog's answer is mechanical and unambiguous: **the group key is the set of head variables other than the aggregate result**. Concretely, for a rule with head `dept_count(D, N)` and aggregate `count(E, N)`, the result variable is `N`, so the group key is `[D]`. Every surviving binding for the rule is bucketed by its `D` value, and each non-empty bucket is reduced to a single output binding.

The engine computes the group key in `aggregate_group_vars/2`:

```elixir
defp aggregate_group_vars(%IR.Atom{terms: terms}, result_var) do
  terms
  |> Enum.flat_map(fn
    {:var, name} -> [name]
    _ -> []
  end)
  |> Enum.reject(fn name -> name == result_var end)
  |> Enum.uniq()
end
```

Constants in the head are ignored (they are not variables), and `result_var` is dropped because it is the *output* of the reduction, not a grouping column. If the head is `total(D, T)` and the constraint is `sum(A, T)`, the groups are keyed by `D`; if the head is `lowest(D, V)` with `min(S, V)`, the groups are also keyed by `D`.

The reduction itself is a one-liner using `Enum.group_by/2`:

```elixir
def group_and_reduce(bindings, group_vars, op, input_var, result_var) do
  bindings
  |> Enum.group_by(fn binding -> Map.take(binding, group_vars) end)
  |> Enum.map(fn {_key, group} ->
    values = Enum.map(group, fn b -> Map.fetch!(b, input_var) end)
    Map.put(hd(group), result_var, compute(op, values))
  end)
end
```

A group only exists because at least one binding produced its key — so `Enum.min/1` and `Enum.max/1` are never called on an empty list. The output binding is the group's first binding extended with `result_var => computed_value`; the other columns of that binding are the surviving group key, which `Join.project/2` then reorganizes into the head tuple.

## Safety Rules

Aggregates are non-monotone: a department whose head count is 2 today might be 3 after more facts arrive, and a rule that already consumed "2" would be wrong. The safety validator (`ExDatalog.Validator.Safety`) rejects any program that could exhibit this. The aggregate-specific checks are layered on top of the ordinary variable-safety rules:

**1. At most one aggregate per rule.** A rule may not mix `count` and `sum`:

```elixir
# Rejected: two aggregates in one rule
Rule.new(
  Atom.new("stats", [Term.var("D"), Term.var("N"), Term.var("T")]),
  [{:positive, Atom.new("emp", [Term.var("E"), Term.var("D"), Term.var("A")])}],
  [Constraint.count(Term.var("E"), Term.var("N")),
   Constraint.sum(Term.var("A"), Term.var("T"))]
)
# => {:error, [%Error{kind: :multiple_aggregates, ...}]}
```

The check is a single length test:

```elixir
defp check_single_aggregate(errors, aggregates, _rule, rule_index) do
  if length(aggregates) > 1 do
    [Error.new(:multiple_aggregates, ..., "a rule may contain at most one " <>
       "aggregate (found #{length(aggregates)}); split into separate rules") | errors]
  else
    errors
  end
end
```

The fix is mechanical: split into two rules, one deriving `dept_count(D, N)` and one deriving `dept_total(D, T)`, both reading from the same `emp` relation.

**2. No aggregate through a self-recursive relation.** A rule whose head relation also appears in its own body — positively or negatively — cannot aggregate:

```elixir
# Rejected: path counts itself
Rule.new(
  Atom.new("path", [Term.var("X"), Term.var("N")]),
  [{:positive, Atom.new("path", [Term.var("X"), Term.var("Y")])}],
  [Constraint.count(Term.var("Y"), Term.var("N"))]
)
# => {:error, [%Error{kind: :aggregate_in_recursion, ...}]}
```

The check inspects every body literal for a relation that matches the head:

```elixir
self_recursive? =
  Enum.any?(rule.body, fn
    {:positive, %Atom{relation: ^head_rel}} -> true
    {:negative, %Atom{relation: ^head_rel}} -> true
    _ -> false
  end)
```

This is a conservative, syntactic recursion check. Mutual recursion through a helper relation is not blocked here, but is caught by the stratification pass described next — the head relation will still be forced into a stratum that depends on itself, which the greedy assigner cannot satisfy without violating the aggregate-stratification invariant.

**3. The aggregate input must be bound.** `count(Z, N)` where `Z` is never bound by a positive body atom is rejected by the ordinary "unbound constraint variable" check, the same path that catches `gt(W, 5)` with an unbound `W`. The aggregate is treated as a constraint with input variables `Constraint.input_variables/1` returns, which for an aggregate is just `[left]`:

```elixir
def input_variables(%__MODULE__{left: left, right: nil}), do: Term.variables([left])
```

**4. The result variable must appear in the head.** Because the result variable is computed by the reduction, it must be projected into the head to be observable at all. The head-safety check already allows an arithmetic *or* aggregate result variable to satisfy head safety:

```elixir
result_vars =
  Enum.flat_map(constraints, fn c ->
    if Constraint.arithmetic?(c) or Constraint.aggregate?(c),
      do: [Constraint.result_variable(c)],
      else: []
  end)
```

So `Rule.head_variables(rule)` including `N` is satisfied by the `count(E, N)` constraint without `N` appearing in any positive body atom. If the head omits the result variable, the aggregate's value is silently dropped — there is no dedicated error for this, but the produced head tuple simply does not carry the computed value.

## Stratification: Forcing the Aggregate Above Its Inputs

Aggregates must be evaluated after every relation they read from is fully materialized. The stratification validator enforces this by running a fixpoint that bumps each aggregate rule's head relation until it sits strictly above all of its positive body relations:

```elixir
defp stabilize_aggregate_strata(strata, aggregate_rules, graph, fuel) do
  bumped =
    Enum.reduce(aggregate_rules, strata, fn rule, acc ->
      head_rel = rule.head.relation
      body_rels =
        for {:positive, %Atom{relation: rel}} <- rule.body, rel != head_rel, do: rel

      required =
        case body_rels do
          [] -> Map.get(acc, head_rel, 0)
          _ -> (body_rels |> Enum.map(&Map.get(acc, &1, 0)) |> Enum.max()) + 1
        end
      ...
    end)

  bumped = propagate_strata(bumped, graph)
  if bumped == strata, do: strata, else: stabilize_aggregate_strata(bumped, ...)
end
```

For `dept_count(D, N) :- emp(E, D), count(E, N)`, suppose `emp` is at stratum 0 (it is an EDB relation). The fixpoint bumps `dept_count` to `max(stratum(emp)) + 1 = 1`. If instead the aggregate reads a *derived* relation, such as

```elixir
mid(K, V)       :- base(K, V)
mid_count(K, N) :- mid(K, V), count(V, N)
```

then `mid` is at stratum 0 (it depends only on EDB `base`), and `mid_count` is bumped to stratum 1. The aggregate test suite asserts exactly this ordering:

```elixir
mid_stratum = Enum.find(ir.rules, fn r -> r.head.relation == "mid" end).stratum
count_stratum = Enum.find(ir.rules, fn r -> r.head.relation == "mid_count" end).stratum
assert count_stratum > mid_stratum
```

Because the aggregate is forced above its inputs, by the time the engine's `eval_aggregate_rule/3` runs against the `full` view, every tuple it will join is already final. There is no half-materialized relation to worry about; the aggregate sees the answer set, not a work-in-progress.

`propagate_strata/2` then re-runs the normal rule so that any relation depending on the aggregate inherits the bumped stratum. The outer fixpoint repeats until a full pass makes no change, with a fuel parameter to guarantee termination.

## The Evaluation Pipeline

Aggregates take a different path through the engine. `Engine.Evaluator.eval_rule_iteration/5` first asks `aggregate_rule?/1` — a body that contains any `{:constraint, %IR.Constraint{op: op}}` with `op` in `[:count, :sum, :min, :max]` makes the rule an aggregate rule:

```elixir
if aggregate_rule?(rule) do
  rule
  |> eval_aggregate_rule(full, ctx)
  |> MapSet.new()
  |> MapSet.difference(existing)
  |> MapSet.to_list()
else
  eval_normal_rule(rule, full, delta, old, ctx, existing)
end
```

Notice what aggregate evaluation *does not* see: no `delta`, no `old`. Aggregates stratify above their inputs, so all source facts are already in `full`. There is no semi-naive delta to consume — the rule fires once, against the final view of its inputs, and the result is whatever the reduction produces.

`eval_aggregate_rule/3` then runs the engine's full pre-grouping pipeline, in this order:

```elixir
defp eval_aggregate_rule(%IR.Rule{} = rule, full, ctx) do
  agg_constraint = find_aggregate(rule.body)

  joined     = join_positive_body([%{}], rule.body, full)
  filtered   = apply_constraints(rule.body, joined, ctx)
  with_cbs   = apply_callbacks(rule.body, filtered, ctx)
  bindings   = apply_negation(rule.body, with_cbs, full)

  %IR.Constraint{op: op, left: {:var, input_var}, result: {:var, result_var}} =
    agg_constraint

  group_vars = aggregate_group_vars(rule.head, result_var)

  bindings
  |> Aggregate.group_and_reduce(group_vars, op, input_var, result_var)
  |> Enum.map(&Join.project(rule.head, &1))
end
```

The pipeline is:

1. **Join** — `join_positive_body/3` starts from `[%{}]` and folds each positive body atom against the `full` view, producing every binding consistent with the body.
2. **Filter** — `apply_constraints/3` runs every *non-aggregate* constraint per binding. Aggregate constraints are explicitly skipped here:

   ```elixir
   constraints =
     for {:constraint, %IR.Constraint{op: op} = c} <- body,
         op not in [:count, :sum, :min, :max],
         do: c
   ```

   This is why a rule can combine `gte(S, 60)` with `count(E, N)` — the comparison filters bindings down to passing scores *before* the count runs. The aggregate test exercises exactly this:

   ```elixir
   Rule.new(
     Atom.new("passing_count", [Term.var("D"), Term.var("N")]),
     [{:positive, Atom.new("score", [Term.var("E"), Term.var("D"), Term.var("S")])}],
     [Constraint.gte(Term.var("S"), Term.const(60)),
      Constraint.count(Term.var("E"), Term.var("N"))]
   )
   # => {:eng, 2}  (alice with 90 and carol with 75 pass; bob with 40 is filtered)
   ```

3. **Callbacks** — `apply_callbacks/3` runs any BEAM predicate literals, the same way as for non-aggregate rules.
4. **Negation** — `apply_negation/3` filters bindings whose negated body atoms are contradicted by a tuple in `full`, exactly as in the negation pipeline.
5. **Group and reduce** — `Aggregate.group_and_reduce/5` buckets the surviving bindings by `group_vars` and reduces each bucket's `input_var` values with `op`, producing one extended binding per non-empty group.
6. **Project** — `Join.project/2` extracts the head's variables from each extended binding into the final head tuple.

The ordering matters: filtering and negation happen *before* grouping, so the aggregate sees only the bindings that survived all per-row predicates. There is no "HAVING" clause — a filter *after* the aggregate would need the result variable to be in scope, which means a follow-up rule reading the aggregate relation. Stratification makes that composition natural: the aggregate relation lives in a higher stratum, so a subsequent rule in an even higher stratum can filter on its results.

## Putting It Together: A Full Example

The test suite's `count_program/0` is a complete, runnable specification of count:

```elixir
defp count_program do
  Program.new()
  |> Program.add_relation("emp", [:atom, :atom])
  |> Program.add_relation("dept_count", [:atom, :integer])
  |> Program.add_fact("emp", [:alice, :eng])
  |> Program.add_fact("emp", [:bob, :eng])
  |> Program.add_fact("emp", [:carol, :ops])
  |> Program.add_rule(
    Rule.new(
      Atom.new("dept_count", [Term.var("D"), Term.var("N")]),
      [{:positive, Atom.new("emp", [Term.var("E"), Term.var("D")])}],
      [Constraint.count(Term.var("E"), Term.var("N"))]
    )
  )
end
```

After materialization:

```elixir
{:ok, knowledge} = ExDatalog.materialize(count_program())
Knowledge.get(knowledge, "dept_count")
# => MapSet containing {:eng, 2} and {:ops, 1}
```

The same shape, with `Constraint.sum/2`, `Constraint.min/2`, or `Constraint.max/2`, produces `dept_total`, `lowest`, or `highest` respectively — only the reducer changes. The grouping, stratification, and pipeline are identical.

## What Is *Not* Here Yet

- **`avg`** — would require a paired `count` and `sum` or rational arithmetic; deferred until integer arithmetic with `div` is deemed stable enough to define `avg` as `div(sum, count)`.
- **Multiple aggregates per rule** — explicitly rejected today. Lifting the restriction means defining a multi-reducer grouping protocol; for now, split into separate rules.
- **Aggregates in recursive rules** — rejected by `:aggregate_in_recursion`. General "monotone aggregates" (e.g. `min` over a lattice) are a research topic and not on the near roadmap.
- **HAVING-style post-aggregate filters** — expressed today by chaining a second rule in a higher stratum that reads the aggregate relation; a dedicated syntax would be a convenience, not a capability gap.

Aggregates are the first feature in ExDatalog that requires the engine to break out of the per-binding loop and look at a whole set of bindings at once. The design keeps that break localized — one new code path in `eval_aggregate_rule/3`, one new module `Constraints.Aggregate`, and one new fixpoint in `force_aggregate_strata/2` — while the rest of the engine, the validator, and the DSL continue to treat aggregates as just another kind of constraint.