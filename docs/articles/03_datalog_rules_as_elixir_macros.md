# Datalog Rules as Elixir Macros: Parsing Heads, Bodies, and Negation at Compile Time

In ExDatalog v0.4.0, the `rule/2` macro transforms Datalog rule declarations from Elixir syntax into internal data structures at compile time. This article walks through the parsing pipeline: how rule heads and bodies are destructured, how uppercase identifiers become logic variables, and how `not_` desugars into negative literals.

## Parsing the Rule Head

The `rule/2` macro receives the head and body as AST fragments:

```elixir
defmacro rule(head, do: body) do
  quote do
    ExDatalog.Schema.__register_rule__(__MODULE__,
      unquote(Macro.escape(head)),
      unquote(Macro.escape(body)))
  end
end
```

`Macro.escape` preserves the AST as data. `__register_rule__/3` runs at compile time, calling `parse_rule_head/1` and `parse_rule_body/1` on the escaped forms.

For `rule ancestor(X, Y) do parent(X, Y) end`, the head AST is:

```elixir
{:ancestor, [line: 1], [{:__aliases__, [alias: false], [:X]}, {:__aliases__, [alias: false], [:Y]}]}
```

`parse_rule_head/1` extracts the relation name and maps each argument through `parse_term/1`:

```elixir
defp parse_rule_head({head_atom, _context, args}) when is_atom(head_atom) and is_list(args) do
  {Atom.to_string(head_atom), Enum.map(args, &parse_term/1)}
end
```

Result: `{"ancestor", [{:var, "X"}, {:var, "Y"}]}`.

## The Prolog Convention: Uppercase = Variable

The DSL follows Prolog convention for term classification:

- **Uppercase identifiers** (`X`, `Y`, `Z`) → logic variables, parsed via the `__aliases__` clause
- **Colon-prefixed atoms** (`:alice`) → constants, parsed via the atom clause
- **`_`** → wildcard

The `parse_term/1` function dispatches on AST node shape:

```elixir
# Module aliases (uppercase) → logic variables
defp parse_term({:__aliases__, _, [alias_name]}) when is_atom(alias_name) do
  {:var, Atom.to_string(alias_name)}
end

# 3-tuple with nil context
defp parse_term({var_name, _context, nil}) when is_atom(var_name) do
  var_str = Atom.to_string(var_name)
  cond do
    var_str == "_" -> :wildcard
    var_str =~ ~r/^[A-Z]/ -> {:var, var_str}
    true -> {:const, var_name}
  end
end

# Bare atoms with colon prefix → constants
defp parse_term(atom) when is_atom(atom) do
  Atom.to_string(atom) |> create_term()
end
```

Why Prolog convention? Three reasons. First, Elixir's AST represents uppercase identifiers as `__aliases__` nodes, giving a clean dispatch point. Second, facts need constants: `fact parent(:alice, :bob)` uses `:alice` and `:bob` as ground values. Third, uppercase variables (`X`, `Y`, `Z`) make logical structure immediately visible:

```elixir
rule ancestor(X, Z) do
  parent(X, Y)
  ancestor(Y, Z)
end
```

The test suite verifies this convention. `rule reachable(:start, Y)` produces `head.terms == [Term.from(:start), Term.var("Y")]` — `:start` is a constant, `Y` is a variable.

## How `not_` Desugars to Negative Literals

Negation uses the `not_` prefix:

```elixir
rule bachelor(P) do
  male(P)
  not_ married(P, _)
end
```

In the AST, `not_ married(P, _)` is `{:not_, meta, [rel_call]}`. `parse_body_call/1` pattern-matches on this:

```elixir
defp parse_body_call({:not_, _, [rel_call]}) do
  {rel_name, args} = parse_rel_call(rel_call)
  terms = Enum.map(args, &parse_term/1)
  {:negative, %ExDatalog.Atom{relation: Atom.to_string(rel_name), terms: terms}}
end
```

The nested `married(P, _)` is parsed as a relational atom, and the entire expression is tagged `{:negative, ...}`. Using `not_` as a prefix avoids collision with Elixir's reserved `not` operator while reading naturally: "not married."

## Constraint Desugaring

Constraint predicates (`gt`, `add`, `is_integer`, etc.) are parsed as function calls. The DSL generates `parse_body_call/1` clauses at compile time:

```elixir
constraint_ops = [:eq, :neq, :gt, :gte, :lt, :lte, :add, :sub, :mul, :div,
                   :is_integer, :is_binary, :is_atom, :starts_with, :contains, :member]

Enum.each(constraint_ops, fn op ->
  defp parse_body_call({unquote(op), _, args}) when is_list(args) do
    {:constraint, build_constraint(unquote(op), args)}
  end
end)
```

For `gt(S, 100_000)`:

```elixir
rule high_earner(P) do
  income(P, S)
  gt(S, 100_000)
end
```

`build_constraint(:gt, [{:__aliases__, ..., [:S]}, 100_000])` parses each argument and delegates to `Constraint.from_tuple`, producing `%Constraint{op: :gt, left: {:var, "S"}, right: {:const, 100_000}, result: nil}`.

The `member` constraint has special handling for literal lists — `member(X, [:a, :b, :c])` wraps the list directly as `{:const, [:a, :b, :c]}` rather than parsing each element.

## From Parsed Data to Rule Structs

After parsing, `__build_program__/3` converts the intermediate forms into `ExDatalog.Rule` structs via `term_from_parsed/1`:

```elixir
defp term_from_parsed({:var, name}), do: ExDatalog.Term.var(name)
defp term_from_parsed({:const, value}), do: ExDatalog.Term.from(value)
defp term_from_parsed(:wildcard), do: ExDatalog.Term.from(:_)
```

The result is exactly the same `Program` struct you'd build by hand with the builder API. The DSL is a zero-overhead compile-time transformation — no macro expansion, no AST walking, no runtime reflection at materialization time.