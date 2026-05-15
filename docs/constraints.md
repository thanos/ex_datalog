# Constraints

Constraints extend Datalog rules beyond simple pattern matching. They appear in
rule bodies alongside relational atoms and filter or extend bindings based on
computed conditions.

## Constraint Types

### Comparison Constraints

Comparison constraints filter bindings. Both `left` and `right` must be bound
before evaluation. The `result` field is `nil`.

| Constructor | Meaning |
|---|---|
| `gt/2` | left > right |
| `lt/2` | left < right |
| `gte/2` | left >= right |
| `lte/2` | left <= right |
| `eq/2` | left == right |
| `neq/2` | left != right |

### Arithmetic Constraints

Arithmetic constraints **bind** a result variable. `left` and `right` must be
bound; after evaluation, `result` is added to the binding environment. All
arithmetic is integer-only. Division by zero filters the binding.

| Constructor | Meaning |
|---|---|
| `add/3` | result = left + right |
| `sub/3` | result = left - right |
| `mul/3` | result = left \* right |
| `div/3` | result = div(left, right) |

### Type Predicate Constraints

Unary filters that check the Elixir type of a bound value. `right` and
`result` are `nil`.

| Constructor | Meaning |
|---|---|
| `type_integer/1` | value is an integer |
| `type_binary/1` | value is a binary (string) |
| `type_atom/1` | value is an atom |

### String Predicate Constraints

Binary filters for string operations. Both operands must be bound and resolve
to binaries. Returns `:filter` if either operand is unbound or not a binary.

| Constructor | Meaning |
|---|---|
| `starts_with/2` | String.starts_with?(left, right) |
| `contains/2` | String.contains?(left, right) |

### Membership Constraints

Tests whether a value is in a constant list. `left` must be bound; `right`
must be a constant list `{:const, [values]}`.

| Constructor | Meaning |
|---|---|
| `member/2` | left in right (list) |

## Evaluation

All constraints are evaluated through `ExDatalog.Constraint.evaluate/3`, which
dispatches to the appropriate module based on the constraint's `op` field. The
dispatch table is closed — adding a new constraint type requires editing the
`constraint_module/1` function in `ExDatalog.Constraint`.

The evaluation context (`ExDatalog.Constraint.Context`) carries storage
backend capabilities. For v0.2.0, no constraint implementation reads from it,
but the plumbing is complete for future use.

## Terms

Constraints use IR terms for their operands:

- `{:var, "X"}` — a variable, looked up in the binding
- `{:const, {:int, 42}}` — a constant integer
- `{:const, {:atom, :alice}}` — a constant atom
- `{:const, {:str, "hello"}}` — a constant string
- `:wildcard` — matches any value without binding