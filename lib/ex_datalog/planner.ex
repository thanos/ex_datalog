defmodule ExDatalog.Planner do
  @moduledoc """
  Query/evaluation planner for ExDatalog.

  The planner sits between the compiled `ExDatalog.IR` and the evaluation
  engine. It produces an `ExDatalog.Planner.Plan` describing the chosen
  `strategy`, the planned strata, the joins (one per positive body atom), and
  the predicates (constraints, aggregates, callbacks).

  The planner is intentionally thin in v0.5.0: it wraps the existing IR strata
  and classifies body elements. It is the seam through which the `:magic_sets`
  strategy is selected and, in future releases, where join ordering and
  cost-based optimization will live.

  ## Strategy selection

  `plan/2` accepts `:strategy` (`:semi_naive` default, or `:magic_sets`). When
  `:magic_sets` is requested, a `:goal` option (`{relation, pattern}`) should be
  supplied; otherwise the planner records the strategy but the engine falls back
  to semi-naive.

  ## Telemetry

  `plan/2` emits `[:ex_datalog, :planner, :start | :stop | :exception]` once per
  call (never per rule).
  """

  alias ExDatalog.Constraint
  alias ExDatalog.IR
  alias ExDatalog.Planner.{Join, Plan, Predicate, Stratum}

  @doc """
  Builds an execution `Plan` from a compiled IR program.

  ## Options

  - `:strategy` — `:semi_naive` (default) or `:magic_sets`
  - `:goal` — `{relation, pattern}` used when `strategy: :magic_sets`

  Returns `{:ok, %Plan{}}`.

  ## Examples

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

  """
  @spec plan(IR.t(), keyword()) :: {:ok, Plan.t()}
  def plan(%IR{} = ir, opts \\ []) do
    metadata = %{relation_count: length(ir.relations), rule_count: length(ir.rules)}

    :telemetry.execute(
      [:ex_datalog, :planner, :start],
      %{system_time: System.system_time()},
      metadata
    )

    start = System.monotonic_time()

    try do
      strategy = Keyword.get(opts, :strategy, :semi_naive)
      goal = Keyword.get(opts, :goal, nil)

      plan = %Plan{
        strategy: strategy,
        strata: build_strata(ir),
        joins: build_joins(ir),
        predicates: build_predicates(ir),
        metadata: %{goal: goal}
      }

      duration = System.monotonic_time() - start

      :telemetry.execute(
        [:ex_datalog, :planner, :stop],
        %{duration: duration},
        Map.put(metadata, :strategy, strategy)
      )

      {:ok, plan}
    rescue
      e ->
        :telemetry.execute(
          [:ex_datalog, :planner, :exception],
          %{duration: System.monotonic_time() - start},
          Map.merge(metadata, %{kind: :error, reason: e})
        )

        reraise e, __STACKTRACE__
    end
  end

  @doc """
  Returns a human-readable description of the plan for a program.

  Accepts the same options as `plan/2`. Validates and compiles the program
  first; returns an error string if compilation fails.

  ## Examples

      iex> alias ExDatalog.{Program, Rule, Atom, Term, Planner}
      iex> program =
      ...>   Program.new()
      ...>   |> Program.add_relation("edge", [:atom, :atom])
      ...>   |> Program.add_relation("path", [:atom, :atom])
      ...>   |> Program.add_rule(
      ...>     Rule.new(
      ...>       Atom.new("path", [Term.var("X"), Term.var("Y")]),
      ...>       [{:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}]
      ...>     )
      ...>   )
      iex> Planner.explain_plan(program) =~ "Strategy: semi_naive"
      true

  """
  @spec explain_plan(ExDatalog.Program.t()) :: String.t()
  def explain_plan(program), do: explain_plan(program, [])

  @spec explain_plan(ExDatalog.Program.t(), keyword()) :: String.t()
  def explain_plan(program, opts) do
    case ExDatalog.compile(program) do
      {:ok, ir} ->
        {:ok, plan} = plan(ir, opts)
        format_plan(plan)

      {:error, errors} ->
        "Cannot plan: compilation failed with #{length(errors)} error(s)"
    end
  end

  # --- Plan construction ---

  defp build_strata(%IR{strata: strata, rules: rules}) do
    Enum.map(strata, fn %IR.Stratum{index: idx, relations: rels} ->
      stratum_rules = Enum.filter(rules, fn r -> r.stratum == idx end)
      %Stratum{index: idx, rules: stratum_rules, relations: rels}
    end)
  end

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

  defp build_predicates(%IR{rules: rules}) do
    rules
    |> Enum.flat_map(fn rule ->
      for {:constraint, c} <- rule.body, do: classify_constraint(c)
    end)
  end

  defp classify_constraint(%IR.Constraint{op: op} = c) do
    %Predicate{kind: constraint_kind(op), op: op, metadata: %{result: c.result}}
  end

  defp constraint_kind(op) do
    cond do
      Constraint.comparison_op?(op) -> :comparison
      Constraint.arithmetic_op?(op) -> :arithmetic
      Constraint.type_op?(op) -> :type
      Constraint.string_op?(op) -> :string
      Constraint.membership_op?(op) -> :membership
      Constraint.aggregate_op?(op) -> :aggregate
      true -> :comparison
    end
  end

  # --- Formatting ---

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
end
