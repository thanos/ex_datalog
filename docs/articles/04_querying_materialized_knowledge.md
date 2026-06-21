# Querying Materialized Knowledge: Post-Materialization Queries with Find/Where

Datalog evaluation is eager: `materialize/2` computes every derivable fact and stops at a fixpoint. The result is a `Knowledge` struct — a fully materialized knowledge base. But raw knowledge is verbose. ExDatalog v0.4.0's `query` macro lets you declare named post-materialization queries that project specific columns from specific relations.

## Declaring Queries

Inside a schema module, you declare queries alongside relations, facts, and rules:

```elixir
defmodule AncestorRules do
  use ExDatalog.Schema

  relation :parent do
    field :parent, :atom
    field :child, :atom
  end

  relation :ancestor do
    field :ancestor, :atom
    field :descendant, :atom
  end

  fact parent(:alice, :bob)
  fact parent(:bob, :carol)
  fact parent(:carol, :dave)

  rule ancestor(X, Y) do
    parent(X, Y)
  end

  rule ancestor(X, Z) do
    parent(X, Y)
    ancestor(Y, Z)
  end

  query :descendants_of_alice do
    find Y
    where ancestor(:alice, Y)
  end
end

{:ok, knowledge} = AncestorRules.materialize()
AncestorRules.query(:descendants_of_alice, knowledge)
#=> [:bob, :carol, :dave]
```

The `find` clause specifies which variables to extract. A single-column `find` returns a list of values. A multi-column `find` returns a list of tuples:

```elixir
query :all_ancestor_pairs do
  find X, Y
  where ancestor(X, Y)
end

AncestorRules.query(:all_ancestor_pairs, knowledge)
#=> [{:alice, :bob}, {:alice, :carol}, {:alice, :dave},
#=>  {:bob, :carol}, {:bob, :dave}, {:carol, :dave}]
```

## How Queries Compile

The `query` macro is parsed at compile time by `__register_query__/3`. `parse_query_block/1` extracts:

1. **Variable names from `find`** — e.g., `["Y"]` or `["X", "Y"]`.
2. **The relation name from `where`** — e.g., `"ancestor"`.
3. **A pattern from `where`** — e.g., `[{:const, :alice}, {:var, "Y"}]`.

These are stored in a `QueryMeta` struct baked into the generated `query/2` function as a literal — no runtime lookup overhead.

## The Engine Room: `Knowledge.match/3`

`__execute_query__/3` performs pattern matching and projection. First, it calls `Knowledge.match/3`:

```elixir
def match(%__MODULE__{relations: rels}, relation, pattern) do
  tuples = Map.get(rels, relation, MapSet.new())

  Enum.reduce(tuples, MapSet.new(), fn tuple, acc ->
    if matches_pattern?(tuple, pattern) do
      MapSet.put(acc, tuple)
    else
      acc
    end
  end)
end
```

The pattern is a list where `:_` matches any value and other values match exactly. The `where` clause `ancestor(:alice, Y)` compiles to `[:alice, :_]` — constants are passed through, variables become wildcards because their values aren't known until the match runs:

```elixir
defp query_term_to_pattern(:wildcard), do: :_
defp query_term_to_pattern({:var, _}), do: :_
defp query_term_to_pattern({:const, value}), do: value
```

## Projection: From Tuples to Targeted Results

After `match/3` returns matching tuples, `project_tuple/3` extracts the columns specified in `find`:

```elixir
defp project_tuple(tuple, find_vars, pattern) do
  positions =
    find_vars
    |> Enum.map(fn var_name ->
      Enum.find_index(pattern, fn
        {:var, ^var_name} -> true
        _ -> false
      end)
    end)

  case positions do
    [single_pos] when is_integer(single_pos) -> elem(tuple, single_pos)
    _ when is_list(positions) ->
      positions
      |> Enum.filter(&(&1 != nil))
      |> Enum.map(fn pos -> elem(tuple, pos) end)
      |> List.to_tuple()
  end
end
```

For `find Y` with pattern `[{:const, :alice}, {:var, "Y"}]`: find position of `"Y"` → index 1, extract `elem(tuple, 1)` from each matched tuple, return a flat list.

For `find X, Y` with pattern `[{:var, "X"}, {:var, "Y"}]`: find positions of both variables, extract both values, return a list of tuples.

The `Enum.sort()` call in `__execute_query__/3` ensures deterministic output regardless of storage backend.

## The Builder API Alternative

Without the DSL, post-materialization queries use `Knowledge.match/3` directly:

```elixir
matched = Knowledge.match(knowledge, "ancestor", [:alice, :_])
results = matched |> MapSet.to_list() |> Enum.map(fn {_, desc} -> desc end) |> Enum.sort()
#=> [:bob, :carol, :dave]
```

The `query` macro automates this `match → project → sort` pipeline with compile-time name resolution.

## Limitations

The current `query` macro operates on a single relation, matches one pattern, and projects specific columns. It doesn't support joins across relations, aggregates, or negation. These limits exist because queries run against already-materialized knowledge. A future query planner could decompose multi-relation queries into join plans that reuse the evaluation engine's matching infrastructure, but for v0.4.0, `Knowledge.match/3` is the foundation.