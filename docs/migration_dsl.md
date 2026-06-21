# Migrating from the Builder API to the DSL

ExDatalog v0.4.0 introduces an Ecto-inspired Schema DSL as the recommended way
to define Datalog programs. The builder API (`Program.add_relation`,
`Program.add_fact`, `Program.add_rule`) remains fully supported as the
lower-level interface.

This guide shows how to migrate existing builder-API code to the DSL.

## Relation Declarations

### Builder API

```elixir
program =
  Program.new()
  |> Program.add_relation("parent", [:atom, :atom])
  |> Program.add_relation("ancestor", [:atom, :atom])
```

### DSL

```elixir
defmodule FamilyRules do
  use ExDatalog.Schema

  relation :parent do
    field :parent, :atom
    field :child, :atom
  end

  relation :ancestor do
    field :ancestor, :atom
    field :descendant, :atom
  end
end
```

## Facts

### Builder API

```elixir
program =
  program
  |> Program.add_fact("parent", [:alice, :bob])
  |> Program.add_fact("parent", [:bob, :carol])
```

### DSL

```elixir
fact parent(:alice, :bob)
fact parent(:bob, :carol)

# Or bulk:
facts :parent do
  row :alice, :bob
  row :bob, :carol
end
```

## Rules

### Builder API (struct-based)

```elixir
Program.add_rule(program,
  Rule.new(
    Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
    [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
  )
)
```

### Builder API (shorthand)

```elixir
Program.add_rule(program,
  {"ancestor", [:X, :Y]},
  [{:positive, {"parent", [:X, :Y]}}]
)
```

### DSL

```elixir
rule ancestor(X, Y) do
  parent(X, Y)
end
```

Lowercase variables are logic variables. Atoms starting with `:` are constants.
`_` is a wildcard.

## Negation

### Builder API

```elixir
Program.add_rule(program, {"bachelor", [:X]}, [
  {:positive, {"male", [:X]}},
  {:negative, {"married", [:X, :_]}}
])
```

### DSL

```elixir
rule bachelor(P) do
  male(P)
  not_ married(P, _)
end
```

## Constraints

### Builder API

```elixir
Program.add_rule(program,
  {"high_earner", [:X]},
  [{:positive, {"income", [:X, :S]}}],
  [{:gt, :S, 100_000}]
)
```

### DSL

```elixir
rule high_earner(P) do
  income(P, S)
  gt(S, 100_000)
end
```

Supported constraint names in the DSL: `eq`, `neq`, `gt`, `gte`, `lt`, `lte`,
`add`, `sub`, `mul`, `div`, `is_integer`, `is_binary`, `is_atom`,
`starts_with`, `contains`, `member`.

## Materialization

### Builder API

```elixir
{:ok, knowledge} = ExDatalog.materialize(program)
```

### DSL

```elixir
{:ok, knowledge} = FamilyRules.materialize()
```

Both accept options: `FamilyRules.materialize(iteration_limit: 100)`

## Queries

The DSL adds a query capability that doesn't have a builder-API equivalent:

```elixir
query :descendants_of_alice do
  find Y
  where ancestor(:alice, Y)
end

{:ok, knowledge} = FamilyRules.materialize()
FamilyRules.query(:descendants_of_alice, knowledge)
#=> [:bob, :carol]
```

The equivalent builder-API code would use `Knowledge.match/3` directly:

```elixir
knowledge
|> Knowledge.match("ancestor", [:alice, :_])
|> MapSet.to_list()
|> Enum.map(fn {_, y} -> y end)
```

## Mixing Both APIs

The DSL's `program/0` returns a standard `ExDatalog.Program` struct. You can
extend it with the builder API:

```elixir
program = FamilyRules.program()

extended =
  program
  |> Program.add_fact("parent", [:carol, :dave])
  |> Program.add_rule(
    Rule.new(
      Atom.new("ancestor", [Term.var("X"), Term.var("Z")]),
      [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])},
       {:positive, Atom.new("ancestor", [Term.var("Y"), Term.var("Z")])}]
    )
  )

{:ok, knowledge} = ExDatalog.materialize(extended)
```

## Variable Conventions

| Pattern | Builder API | DSL |
|---------|-------------|-----|
| Logic variable | `Term.var("X")` or `:X` | `X` (lowercase in DSL) |
| Constant | `Term.from(:alice)` or `:alice` | `:alice` |
| Wildcard | `Term.from(:_)` or `:_` | `_` or `wildcard()` |