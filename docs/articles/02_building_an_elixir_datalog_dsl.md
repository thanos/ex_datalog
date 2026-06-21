# Building an Elixir Datalog DSL: The Design of ExDatalog v0.4.0's Schema Macro

ExDatalog v0.3.0 offered a builder API: you assembled programs by piping `Program.add_relation/3`, `Program.add_fact/3`, and `Program.add_rule/2` calls. It worked, but it looked like configuration code, not like expressing logical rules. Version 0.4.0 introduces the Schema DSL — a set of compile-time macros that let you declare relations, facts, rules, and queries inside an Elixir module.

This article walks through the design decisions and explains how the DSL compiles down to the builder API.

## Why Ecto-Inspired Macros?

ExDatalog's Schema DSL follows the same pattern as Ecto's `Ecto.Schema`. Both need to collect declarations at compile time and generate runtime functions from those declarations. The `@before_compile` pattern is essential: you can't generate `program/0` until all `relation`, `fact`, and `rule` macros have finished registering their data.

```elixir
defmacro __using__(_opts) do
  quote do
    import ExDatalog.Schema, only: [relation: 2, fact: 1, facts: 2, rule: 2, query: 2, wildcard: 0]

    Module.register_attribute(__MODULE__, :ex_datalog_relations, accumulate: true)
    Module.register_attribute(__MODULE__, :ex_datalog_facts, accumulate: true)
    Module.register_attribute(__MODULE__, :ex_datalog_rules, accumulate: true)
    Module.register_attribute(__MODULE__, :ex_datalog_queries, accumulate: true)

    @before_compile ExDatalog.Schema
  end
end
```

Four module attributes accumulate declarations. Each macro call appends to the corresponding attribute, and `__before_compile__` reads them all to generate `program/0`, `materialize/0`, `queries/0`, and `query/2`:

```elixir
defmacro __before_compile__(env) do
  relations = Module.get_attribute(env.module, :ex_datalog_relations) |> Enum.reverse()
  facts = Module.get_attribute(env.module, :ex_datalog_facts) |> Enum.reverse()
  rules = Module.get_attribute(env.module, :ex_datalog_rules) |> Enum.reverse()
  queries = Module.get_attribute(env.module, :ex_datalog_queries) |> Enum.reverse()

  quote do
    def program do
      ExDatalog.Schema.__build_program__(unquote(Macro.escape(relations)),
                                         unquote(Macro.escape(facts)),
                                         unquote(Macro.escape(rules)))
    end

    def materialize(opts \\ []) do
      ExDatalog.materialize(program(), opts)
    end

    def queries do
      unquote(Macro.escape(Map.new(queries, fn q -> {q.name, q} end)))
    end

    def query(name, knowledge) do
      ExDatalog.Schema.__execute_query__(name, knowledge, unquote(Macro.escape(queries)))
    end
  end
end
```

`Enum.reverse/1` restores declaration order because `accumulate: true` prepends. `Macro.escape/1` converts the Elixir data structures into AST literals that the `quote` block can inject.

## The Variable Convention

The DSL follows Prolog convention for distinguishing variables from constants: uppercase identifiers are logic variables, lowercase atoms and colon-prefixed atoms are constants, and `_` is a wildcard.

This convention is driven by how Elixir's AST represents identifiers. Uppercase names like `X` and `Y` are parsed as `__aliases__` nodes, producing a distinct AST shape from lowercase variables. The `parse_term/1` function dispatches on these shapes:

```elixir
# Uppercase identifiers (module aliases) → logic variables
defp parse_term({:__aliases__, _, [alias_name]}) when is_atom(alias_name) do
  {:var, Atom.to_string(alias_name)}
end

# Bare identifiers with nil context
defp parse_term({var_name, _context, nil}) when is_atom(var_name) do
  var_str = Atom.to_string(var_name)
  cond do
    var_str == "_" -> :wildcard
    var_str =~ ~r/^[A-Z]/ -> {:var, var_str}
    true -> {:const, var_name}
  end
end

# Atoms with colon prefix → constants
defp parse_term(atom) when is_atom(atom) do
  Atom.to_string(atom) |> create_term()
end
```

| DSL Syntax | Internal Form | Meaning |
|---|---|---|
| `X`, `Y`, `Z` | `{:var, "X"}`, `{:var, "Y"}` | Logic variable |
| `:alice`, `:bob` | `{:const, :alice}`, `{:const, :bob}` | Constant |
| `_` | `:wildcard` | Anonymous variable |

The test suite confirms: `rule reachable(:start, Y)` produces `head.terms == [Term.from(:start), Term.var("Y")]`, where `:start` is a constant and `Y` is a variable.

## Macro Hygiene and `Macro.escape`

The `rule/2` macro uses `Macro.escape` on both the head and body, which is critical. Without escaping, Elixir would try to evaluate the AST as runtime code. With escaping, the AST is preserved as data and passed to `__register_rule__/3` at compile time:

```elixir
defmacro rule(head, do: body) do
  quote do
    ExDatalog.Schema.__register_rule__(__MODULE__,
      unquote(Macro.escape(head)),
      unquote(Macro.escape(body)))
  end
end
```

This means the DSL never evaluates `parent(X, Y)` as a function call. It parses the AST representation `{:parent, [line: N], [{:__aliases__, ..., [:X]}, {:__aliases__, ..., [:Y]}]}` and extracts the relation name and terms as data.

## What the DSL Doesn't Do (Yet)

The v0.4.0 DSL deliberately omits some features:

- **Aggregates** — the syntax `rule employee_count(dept, agg(:count, emp))` is parsed but returns `%UnsupportedFeature{feature: :aggregates}`. Materializing such a program fails with a clear error.
- **Query planning** — the `query` macro calls `Knowledge.match/3` on materialized knowledge. There's no query optimizer or cost model.
- **Schema validation** — the DSL doesn't check at compile time that a `fact` references a declared relation, or that a `rule` head's arity matches its `relation` declaration. These checks happen at runtime through the builder API and `Validator`.

The DSL's job in v0.4.0 is to make the common case ergonomic and readable. The builder API remains the fully-capable interface for dynamic program construction or features the DSL doesn't yet cover.

Good Elixir macros don't hide complexity — they eliminate boilerplate. The Schema DSL compiles to the same builder API, so every macro feature is also available programmatically. The `__build_program__/3` function iterates over the collected relations, facts, and rules, calling `Program.add_relation/3`, `Program.add_fact/3`, and `Program.add_rule/2` — the exact same pipeline a hand-written builder would use. At runtime, there's no macro expansion, no AST walking — just the builder pipeline running on pre-computed data structures.

This design also means you can mix both approaches: define the static structure of your program with the DSL, then extend it with the builder API at runtime. The test suite verifies this with a backward-compatibility test that defines a schema, calls `program/0`, then adds additional facts and rules via `Program.add_fact/3` and `Program.add_rule/2` before materializing.