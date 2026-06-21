defmodule ExDatalog.UnsupportedFeature do
  @moduledoc """
  Returned when a DSL feature is recognized but not yet implemented.

  The `feature` field names the unsupported feature.
  The `planned_for` field indicates the target release.

  ## Examples

      iex> uf = %ExDatalog.UnsupportedFeature{feature: :aggregates, planned_for: "v0.6.0"}
      iex> uf.feature
      :aggregates
      iex> uf.planned_for
      "v0.6.0"
  """

  @enforce_keys [:feature, :planned_for]
  defstruct [:feature, :planned_for]

  @type t :: %__MODULE__{feature: atom(), planned_for: String.t()}
end

defmodule ExDatalog.Schema do
  @moduledoc """
  An Ecto-inspired DSL for defining Datalog programs.

  `use ExDatalog.Schema` in a module to declare relations, facts, rules,
  and queries. The module then exposes `program/0`, `materialize/0`,
  and `query/2` functions.

  ## Example

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

        fact parent(:alice, :bob)
        fact parent(:bob, :carol)

        rule ancestor(x, y) do
          parent(x, y)
        end

        rule ancestor(x, z) do
          parent(x, y)
          ancestor(y, z)
        end

        query :descendants_of_alice do
          find y
          where ancestor(:alice, y)
        end
      end

      {:ok, knowledge} = FamilyRules.materialize()
      FamilyRules.query(:descendants_of_alice, knowledge)
      #=> [:bob, :carol]

  ## Relation DSL

  Relations declare named schemas with typed fields:

      relation :parent do
        field :parent, :atom
        field :child, :atom
      end

  Supported field types: `:atom`, `:integer`, `:string`, `:any`.

  ## Fact DSL

  Facts assert ground tuples:

      fact parent(:alice, :bob)

  Bulk facts:

      facts :parent do
        row :alice, :bob
        row :bob, :carol
      end

  ## Rule DSL

  Rules derive new facts. Lowercase identifiers are logic variables,
  atoms starting with `:` are constants, and `_` is a wildcard:

      rule ancestor(x, y) do
        parent(x, y)
      end

  Negation uses `not_`:

      rule bachelor(p) do
        male(p)
        not_ married(p, _)
      end

  Constraints use named predicates:

      rule high_earner(p) do
        income(p, salary)
        gt(salary, 100_000)
      end

  Supported constraints: `eq`, `neq`, `gt`, `gte`, `lt`, `lte`,
  `add`, `sub`, `mul`, `div`, `is_integer`, `is_binary`, `is_atom`,
  `starts_with`, `contains`, `member`.

  ## Query DSL

  Queries define named post-materialization lookups:

      query :all_ancestors do
        find x, y
        where ancestor(x, y)
      end

  Queries operate on materialized knowledge and use `Knowledge.match/3`
  internally.

  ## Aggregate Syntax (Preview)

  Aggregates are parsed but not yet executable:

      rule employee_count(dept, agg(:count, emp)) do
        employee(emp, dept)
      end

  Attempting to materialize a program with aggregates returns
  `{:error, %ExDatalog.UnsupportedFeature{feature: :aggregates}}`.

  ## Backward Compatibility

  The DSL compiles into the existing `Program` builder API. All existing
  builder APIs (`Program.add_relation/3`, `Program.add_fact/3`,
  `Program.add_rule/2,3,4`, `ExDatalog.materialize/2`) continue to work.
  """

  defmodule Field do
    @moduledoc false
    @enforce_keys [:name, :type]
    defstruct [:name, :type]

    @type t :: %__MODULE__{name: atom(), type: ExDatalog.Program.ir_type()}
  end

  defmodule RelationMeta do
    @moduledoc false
    @enforce_keys [:name, :fields]
    defstruct [:name, :fields]

    @type t :: %__MODULE__{name: atom(), fields: [ExDatalog.Schema.Field.t()]}
  end

  defmodule QueryMeta do
    @moduledoc false
    @enforce_keys [:name, :relation, :pattern, :find_vars]
    defstruct [:name, :relation, :pattern, :find_vars]

    @type t :: %__MODULE__{
            name: atom(),
            relation: String.t(),
            pattern: [term()],
            find_vars: [String.t()]
          }
  end

  @doc false
  defmacro __using__(_opts) do
    quote do
      import ExDatalog.Schema,
        only: [relation: 2, fact: 1, facts: 2, rule: 2, query: 2, wildcard: 0]

      Module.register_attribute(__MODULE__, :ex_datalog_relations, accumulate: true)
      Module.register_attribute(__MODULE__, :ex_datalog_facts, accumulate: true)
      Module.register_attribute(__MODULE__, :ex_datalog_rules, accumulate: true)
      Module.register_attribute(__MODULE__, :ex_datalog_queries, accumulate: true)

      @before_compile ExDatalog.Schema
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    relations = Module.get_attribute(env.module, :ex_datalog_relations) |> Enum.reverse()
    facts = Module.get_attribute(env.module, :ex_datalog_facts) |> Enum.reverse()
    rules = Module.get_attribute(env.module, :ex_datalog_rules) |> Enum.reverse()
    queries = Module.get_attribute(env.module, :ex_datalog_queries) |> Enum.reverse()

    relation_names = MapSet.new(relations, fn rel -> Atom.to_string(rel.name) end)

    Enum.each(facts, fn {rel_name, _values} ->
      unless MapSet.member?(relation_names, Atom.to_string(rel_name)) do
        raise ExDatalog.DSL.CompileError,
          message:
            "fact #{rel_name}: relation #{inspect(Atom.to_string(rel_name))} is not declared"
      end
    end)

    Enum.each(queries, fn q ->
      unless MapSet.member?(relation_names, q.relation) do
        raise ExDatalog.DSL.CompileError,
          message: "query #{q.name}: relation #{inspect(q.relation)} is not declared"
      end
    end)

    quote do
      @doc """
      Returns the `ExDatalog.Program` built from this schema's relations,
      facts, and rules.
      """
      @spec program() :: ExDatalog.Program.t()
      def program do
        ExDatalog.Schema.__build_program__(
          unquote(Macro.escape(relations)),
          unquote(Macro.escape(facts)),
          unquote(Macro.escape(rules))
        )
      end

      @doc """
      Materializes this schema's program. Accepts the same options as
      `ExDatalog.materialize/2`.
      """
      @spec materialize(keyword()) :: {:ok, ExDatalog.Knowledge.t()} | {:error, term()}
      def materialize(opts \\ []) do
        ExDatalog.materialize(program(), opts)
      end

      @doc """
      Returns a map of query names to their metadata.
      """
      @spec queries() :: %{atom() => ExDatalog.Schema.QueryMeta.t()}
      def queries do
        unquote(Macro.escape(Map.new(queries, fn q -> {q.name, q} end)))
      end

      @doc """
      Executes a named query against materialized knowledge.

      Returns a list of results. For single-column `find`, returns a list of
      values. For multi-column `find`, returns a list of tuples.
      """
      @spec query(atom(), ExDatalog.Knowledge.t()) :: [term()]
      def query(name, knowledge) do
        ExDatalog.Schema.__execute_query__(name, knowledge, unquote(Macro.escape(queries)))
      end
    end
  end

  @doc false
  def __build_program__(relations, facts, rules) do
    program = ExDatalog.Program.new()

    program =
      Enum.reduce(relations, program, fn rel_meta, acc ->
        types = Enum.map(rel_meta.fields, & &1.type)
        ExDatalog.Program.add_relation(acc, Atom.to_string(rel_meta.name), types)
      end)

    program =
      Enum.reduce(facts, program, fn {rel_name, values}, acc ->
        result = ExDatalog.Program.add_fact(acc, Atom.to_string(rel_name), values)

        case result do
          {:error, msg} ->
            raise ExDatalog.DSL.CompileError,
              message: "fact #{rel_name}(#{Enum.map_join(values, ", ", &inspect/1)}): #{msg}"

          prog ->
            prog
        end
      end)

    program =
      Enum.reduce(rules, program, fn rule_data, acc ->
        {{head_rel, head_terms}, body_literals, constraints} = rule_data

        head_atom = %ExDatalog.Atom{
          relation: head_rel,
          terms: Enum.map(head_terms, &term_from_parsed/1)
        }

        body =
          Enum.map(body_literals, fn
            {:positive, %ExDatalog.Atom{} = atom} ->
              {:positive,
               %ExDatalog.Atom{atom | terms: Enum.map(atom.terms, &term_from_parsed/1)}}

            {:negative, %ExDatalog.Atom{} = atom} ->
              {:negative,
               %ExDatalog.Atom{atom | terms: Enum.map(atom.terms, &term_from_parsed/1)}}
          end)

        rule = ExDatalog.Rule.new(head_atom, body, constraints)

        case ExDatalog.Program.add_rule(acc, rule) do
          {:error, msg} ->
            raise ExDatalog.DSL.CompileError,
              message: "rule #{head_rel}/#{length(head_terms)}: #{msg}"

          prog ->
            prog
        end
      end)

    validate_rules!(program, rules)
    program
  end

  defp validate_rules!(_program, rules) do
    Enum.each(rules, fn {{head_rel, head_terms}, body_literals, constraints} ->
      head_vars =
        head_terms |> Enum.filter(&match?({:var, _}, &1)) |> Enum.map(fn {:var, n} -> n end)

      positive_vars =
        body_literals
        |> Enum.flat_map(fn
          {:positive, %ExDatalog.Atom{terms: terms}} ->
            Enum.flat_map(terms, fn
              {:var, n} -> [n]
              _ -> []
            end)

          _ ->
            []
        end)

      constraint_vars =
        Enum.flat_map(constraints, fn
          %ExDatalog.Constraint{result: {:var, n}} -> [n]
          %ExDatalog.Constraint{} -> []
          _ -> []
        end)

      safe_vars = (positive_vars ++ constraint_vars) |> Enum.uniq()
      unsafe = head_vars -- safe_vars

      if unsafe != [] do
        raise ExDatalog.DSL.CompileError,
          message:
            "rule #{head_rel}/#{length(head_terms)}: variable(s) #{Enum.join(unsafe, ", ")} appear in the rule head but not in any positive body literal"
      end
    end)

    :ok
  end

  defp term_from_parsed({:var, name}), do: ExDatalog.Term.var(name)
  defp term_from_parsed({:const, value}), do: ExDatalog.Term.from(value)
  defp term_from_parsed(:wildcard), do: ExDatalog.Term.from(:_)

  @doc false
  def __execute_query__(name, knowledge, queries) when is_list(queries) do
    query_map = Map.new(queries, fn q -> {q.name, q} end)
    __execute_query__(name, knowledge, query_map)
  end

  def __execute_query__(name, knowledge, queries) when is_map(queries) do
    case Map.get(queries, name) do
      nil ->
        raise ArgumentError, "unknown query #{inspect(name)}"

      q ->
        pattern = Enum.map(q.pattern, &query_term_to_pattern/1)
        matched = ExDatalog.Knowledge.match(knowledge, q.relation, pattern)

        matched
        |> MapSet.to_list()
        |> Enum.sort()
        |> Enum.map(fn tuple ->
          project_tuple(tuple, q.find_vars, q.pattern)
        end)
    end
  end

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
      [nil] ->
        tuple

      [single_pos] when is_integer(single_pos) ->
        elem(tuple, single_pos)

      _ when is_list(positions) ->
        positions
        |> Enum.filter(&(&1 != nil))
        |> Enum.map(fn pos -> elem(tuple, pos) end)
        |> List.to_tuple()
    end
  end

  defp query_term_to_pattern(:wildcard), do: :_
  defp query_term_to_pattern({:var, _}), do: :_
  defp query_term_to_pattern({:const, value}), do: value

  # --- Relation macro ---

  @doc """
  Declares a relation with typed fields.

      relation :parent do
        field :parent, :atom
        field :child, :atom
      end

  Supported types: `:atom`, `:integer`, `:string`, `:any`.
  """
  defmacro relation(name, do: block) do
    quote do
      ExDatalog.Schema.__define_relation__(
        __MODULE__,
        unquote(name),
        unquote(Macro.escape(block))
      )
    end
  end

  @doc false
  def __define_relation__(module, name, block) do
    fields = extract_fields(block)

    Module.put_attribute(module, :ex_datalog_relations, %ExDatalog.Schema.RelationMeta{
      name: name,
      fields: fields
    })
  end

  defp extract_fields({:__block__, _, expressions}) do
    Enum.flat_map(expressions, &extract_field/1)
  end

  defp extract_fields({:field, _, [name, type]}) do
    [%ExDatalog.Schema.Field{name: name, type: type}]
  end

  defp extract_fields(single) do
    extract_field(single)
  end

  defp extract_field({:field, _, [name, type]}) do
    [%ExDatalog.Schema.Field{name: name, type: type}]
  end

  defp extract_field(_), do: []

  # --- Fact macros ---

  @doc """
  Declares a ground fact.

      fact parent(:alice, :bob)

  The relation must be declared before the fact.
  """
  defmacro fact(rel_call) do
    {rel_name, args} = parse_rel_call(rel_call)

    quote do
      ExDatalog.Schema.__register_fact__(
        __MODULE__,
        unquote(rel_name),
        unquote(Macro.escape(args))
      )
    end
  end

  @doc false
  def __register_fact__(module, rel_name, args) do
    Module.put_attribute(module, :ex_datalog_facts, {rel_name, args})
  end

  @doc """
  Declares multiple facts for the same relation.

      facts :parent do
        row :alice, :bob
        row :bob, :carol
      end
  """
  defmacro facts(rel_name, do: block) do
    rows = extract_rows(block)

    quote do
      ExDatalog.Schema.__register_facts__(
        __MODULE__,
        unquote(rel_name),
        unquote(Macro.escape(rows))
      )
    end
  end

  @doc false
  def __register_facts__(module, rel_name, rows) do
    Enum.each(rows, fn args ->
      Module.put_attribute(module, :ex_datalog_facts, {rel_name, args})
    end)
  end

  defp extract_rows({:__block__, _, expressions}) do
    Enum.flat_map(expressions, &extract_row/1)
  end

  defp extract_rows({:row, _, args}) do
    [args]
  end

  defp extract_rows(_), do: []

  defp extract_row({:row, _, args}), do: [args]
  defp extract_row(_), do: []

  # --- Rule macro ---

  @doc """
  Declares a Datalog rule.

  Lowercase identifiers in the head and body are logic variables.
  Atoms starting with `:` are constants. `_` is a wildcard.

      rule ancestor(x, y) do
        parent(x, y)
      end

  Negation uses `not_`:

      rule bachelor(p) do
        male(p)
        not_ married(p, _)
      end

  Constraints use named predicates:

      rule high_earner(p) do
        income(p, salary)
        gt(salary, 100_000)
      end
  """
  defmacro rule(head, do: body) do
    quote do
      ExDatalog.Schema.__register_rule__(
        __MODULE__,
        unquote(Macro.escape(head)),
        unquote(Macro.escape(body))
      )
    end
  end

  @doc false
  def __register_rule__(module, head, body) do
    {head_rel, head_terms} = parse_rule_head(head)
    {body_literals, constraints} = parse_rule_body(body)

    rule_data = {{head_rel, head_terms}, body_literals, constraints}
    Module.put_attribute(module, :ex_datalog_rules, rule_data)
  end

  defp parse_rule_head({head_atom, _context, args}) when is_atom(head_atom) and is_list(args) do
    {Atom.to_string(head_atom), Enum.map(args, &parse_term/1)}
  end

  defp parse_rule_head({head_atom, _context, nil}) when is_atom(head_atom) do
    {Atom.to_string(head_atom), []}
  end

  defp parse_rule_head(_other) do
    raise CompileError,
      description: "rule head must be a relation call like `ancestor(x, y)`"
  end

  defp parse_term({:wildcard, _, []}) do
    :wildcard
  end

  defp parse_term({var_name, _, nil}) when is_atom(var_name) do
    var_str = Atom.to_string(var_name)

    cond do
      var_str == "_" -> :wildcard
      var_str =~ ~r/^[A-Z]/ -> {:var, var_str}
      true -> {:const, var_name}
    end
  end

  defp parse_term({:__aliases__, _, [alias_name]}) when is_atom(alias_name) do
    {:var, Atom.to_string(alias_name)}
  end

  defp parse_term(atom) when is_atom(atom) do
    Atom.to_string(atom) |> create_term()
  end

  defp parse_term(integer) when is_integer(integer), do: {:const, integer}
  defp parse_term(string) when is_binary(string), do: {:const, string}

  defp parse_term(other) do
    raise CompileError,
      description: "unsupported term in DSL: #{inspect(other)}"
  end

  defp create_term(name) when is_binary(name) do
    cond do
      name == "_" -> :wildcard
      String.match?(name, ~r/^[A-Z]/) -> {:var, name}
      true -> {:const, String.to_atom(name)}
    end
  end

  defp parse_rule_body({:__block__, _, expressions}) do
    expressions
    |> Enum.map(&parse_body_call/1)
    |> Enum.reduce({[], []}, fn
      {:positive, atom}, {body, constraints} ->
        {body ++ [{:positive, atom}], constraints}

      {:negative, atom}, {body, constraints} ->
        {body ++ [{:negative, atom}], constraints}

      {:constraint, c}, {body, constraints} ->
        {body, constraints ++ [c]}

      {:aggregate, agg}, {body, constraints} ->
        {body, constraints ++ [agg]}
    end)
  end

  defp parse_rule_body(single_expr) do
    parse_rule_body({:__block__, [], [single_expr]})
  end

  defp parse_body_call({:not_, _, [rel_call]}) do
    {rel_name, args} = parse_rel_call(rel_call)
    terms = Enum.map(args, &parse_term/1)
    {:negative, %ExDatalog.Atom{relation: Atom.to_string(rel_name), terms: terms}}
  end

  defp parse_body_call({:not_, _, [rel_call, _opts]}) do
    parse_body_call({:not_, [], [rel_call]})
  end

  defp parse_body_call({:agg, _, args}) when is_list(args) do
    {:aggregate, %ExDatalog.UnsupportedFeature{feature: :aggregates, planned_for: "v0.6.0"}}
  end

  constraint_ops = [
    :eq,
    :neq,
    :gt,
    :gte,
    :lt,
    :lte,
    :add,
    :sub,
    :mul,
    :div,
    :is_integer,
    :is_binary,
    :is_atom,
    :starts_with,
    :contains,
    :member
  ]

  Enum.each(constraint_ops, fn op ->
    defp parse_body_call({unquote(op), _, args}) when is_list(args) do
      {:constraint, build_constraint(unquote(op), args)}
    end
  end)

  defp parse_body_call({rel_atom, _, args}) when is_atom(rel_atom) and is_list(args) do
    terms = Enum.map(args, &parse_term/1)
    {:positive, %ExDatalog.Atom{relation: Atom.to_string(rel_atom), terms: terms}}
  end

  defp parse_body_call({rel_atom, _, nil}) when is_atom(rel_atom) do
    {:positive, %ExDatalog.Atom{relation: Atom.to_string(rel_atom), terms: []}}
  end

  defp parse_body_call(other) do
    raise CompileError,
      description: "unsupported body expression in rule: #{inspect(other)}"
  end

  constraint_2_arity = [:eq, :neq, :gt, :gte, :lt, :lte, :starts_with, :contains]
  constraint_3_arity = [:add, :sub, :mul, :div]
  constraint_1_arity = [:is_integer, :is_binary, :is_atom]
  constraint_member = [:member]

  Enum.each(constraint_2_arity, fn op ->
    defp build_constraint(unquote(op), [left, right]) do
      ExDatalog.Constraint.from_tuple({unquote(op), parse_term(left), parse_term(right)})
    end
  end)

  Enum.each(constraint_3_arity, fn op ->
    defp build_constraint(unquote(op), [left, right, result]) do
      ExDatalog.Constraint.from_tuple(
        {unquote(op), parse_term(left), parse_term(right), parse_term(result)}
      )
    end
  end)

  Enum.each(constraint_1_arity, fn op ->
    defp build_constraint(unquote(op), [arg]) do
      ExDatalog.Constraint.from_tuple({unquote(op), parse_term(arg)})
    end
  end)

  Enum.each(constraint_member, fn op ->
    defp build_constraint(unquote(op), [elem, list_or_var]) do
      left = parse_term(elem)
      right = if is_list(list_or_var), do: {:const, list_or_var}, else: parse_term(list_or_var)
      ExDatalog.Constraint.from_tuple({unquote(op), left, right})
    end
  end)

  defp build_constraint(op, args) do
    raise CompileError,
      description: "unsupported constraint #{op}/#{length(args)}: #{inspect(args)}"
  end

  # --- Query macro ---

  @doc """
  Declares a named post-materialization query.

      query :descendants_of_alice do
        find y
        where ancestor(:alice, y)
      end

  The `find` clause specifies which variables to extract.
  The `where` clause specifies the relation and pattern to match.
  """
  defmacro query(name, do: block) do
    quote do
      ExDatalog.Schema.__register_query__(__MODULE__, unquote(name), unquote(Macro.escape(block)))
    end
  end

  @doc false
  def __register_query__(module, name, block) do
    {find_vars, relation, pattern} = parse_query_block(block)

    Module.put_attribute(module, :ex_datalog_queries, %ExDatalog.Schema.QueryMeta{
      name: name,
      relation: relation,
      pattern: pattern,
      find_vars: find_vars
    })
  end

  defp parse_query_block({:__block__, _, expressions}) do
    find_vars = []
    relation = nil

    Enum.reduce(expressions, {find_vars, relation}, fn
      {:find, _, vars}, {_, rel} ->
        vars_list = if is_list(vars), do: vars, else: [vars]
        var_names = Enum.map(vars_list, &extract_var_name/1)
        {var_names, rel}

      {:where, _, [{rel_atom, _, args}]}, {find_vars, _} ->
        {find_vars, Atom.to_string(rel_atom), Enum.map(args, &parse_query_term/1)}

      {:where, _, [{rel_atom, _, nil}]}, {find_vars, _} ->
        {find_vars, Atom.to_string(rel_atom), []}
    end)
  end

  defp parse_query_block({:find, _, [find_var]}) do
    parse_query_block({:__block__, [], [{:find, [], [find_var]}, {:where, [], [{:_, [], nil}]}]})
  end

  defp parse_query_term({:__aliases__, _, [alias_name]} = _var) when is_atom(alias_name) do
    {:var, Atom.to_string(alias_name)}
  end

  defp parse_query_term({_var_name, _, nil} = var) when is_tuple(var) do
    parse_term(var)
  end

  defp parse_query_term(atom) when is_atom(atom) do
    parse_term(atom)
  end

  defp parse_query_term(integer) when is_integer(integer), do: {:const, integer}
  defp parse_query_term(string) when is_binary(string), do: {:const, string}

  defp extract_var_name({:__aliases__, _, [alias_name]}) when is_atom(alias_name) do
    Atom.to_string(alias_name)
  end

  defp extract_var_name({var_name, _, nil}) when is_atom(var_name) do
    Atom.to_string(var_name)
  end

  # --- Helpers ---

  defp parse_rel_call({rel_atom, _, args}) when is_atom(rel_atom) and is_list(args) do
    {rel_atom, args}
  end

  defp parse_rel_call({rel_atom, _, nil}) when is_atom(rel_atom) do
    {rel_atom, []}
  end

  defp parse_rel_call(rel_atom) when is_atom(rel_atom) do
    {rel_atom, []}
  end

  @doc """
  Explicit wildcard for use in rule bodies and queries.

  Inside DSL rule and query bodies, `_` is treated as a wildcard.
  If Elixir's treatment of `_` as a special form causes issues,
  use `wildcard()` as an explicit alternative.

  ## Examples

      iex> ExDatalog.Schema.wildcard()
      :wildcard

      rule bachelor(p) do
        male(p)
        not_ married(p, wildcard())
      end
  """
  @spec wildcard() :: :wildcard
  def wildcard, do: :wildcard
end
