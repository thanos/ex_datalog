defmodule ExDatalog.Engine.Naive do
  @moduledoc """
  Semi-naive fixpoint evaluation engine.

  Evaluates a compiled IR program stratum by stratum. Within each stratum, it
  iterates until no new facts are derived (fixpoint), using the k-position
  delta algorithm to avoid redundant derivations.

  ## Negation

  Rules with negative body atoms must be stratified: every relation that appears
  under negation must belong to a strictly lower stratum than the rule's head
  relation. The engine validates this invariant before evaluation and returns
  `{:error, reason}` for unstratifiable programs.

  Negative atoms are evaluated against the fully-materialised `full` relation
  snapshot, ensuring correctness under stratified evaluation.

  ## Provenance

  When the `:explain` option is `true`, the result's `provenance` field records
  which rule derived each fact. Base facts (EDB) are attributed as `:base`.
  When `:explain` is `false` (default), provenance tracking is disabled entirely,
  ensuring zero overhead.

  ## Algorithm

  For each stratum:

  1. Load EDB base facts into storage.
  2. `full` ← snapshot of all current facts.
  3. `delta` ← `full` (all EDB facts are "new" on the first iteration).
  4. `old` ← empty (nothing existed "before" iteration 0).
  5. Loop:
     a. Evaluate all stratum rules using k-position delta with `(full, delta, old)`.
     b. Collect newly derived tuples; remove those already in `full`.
     c. If no new tuples: fixpoint reached, stop.
     d. Insert new tuples into storage.
     e. `old` ← `full` (snapshot before this iteration).
     f. `full` ← new snapshot.
     g. `delta` ← `full \ old` (per-relation difference).

  ## Options

  - `:storage` — storage module (default: `ExDatalog.Storage.Map`)
  - `:max_iterations` — per-stratum iteration limit (default: `10_000`)
  - `:timeout_ms` — per-stratum wall-clock timeout in ms (default: `30_000`)
  - `:explain` — enable provenance tracking (default: `false`)
  """

  @behaviour ExDatalog.Engine

  alias ExDatalog.Engine.Evaluator
  alias ExDatalog.IR
  alias ExDatalog.Result

  @default_max_iterations 10_000
  @default_timeout_ms 30_000

  @impl ExDatalog.Engine
  @spec name() :: String.t()
  def name, do: "naive"

  @impl ExDatalog.Engine
  @spec evaluate(IR.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def evaluate(%IR{} = ir, opts \\ []) do
    case validate_stratification(ir) do
      {:error, _} = err ->
        err

      :ok ->
        do_evaluate(ir, opts)
    end
  end

  defp do_evaluate(%IR{} = ir, opts) do
    storage_mod = Keyword.get(opts, :storage, ExDatalog.Storage.Map)
    max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    explain = Keyword.get(opts, :explain, false)

    start_time = System.monotonic_time(:microsecond)

    schemas =
      ir.relations
      |> Enum.map(fn %IR.Relation{name: name, arity: arity, types: types} ->
        {name, %{arity: arity, types: types}}
      end)
      |> Map.new()

    state0 = storage_mod.init(schemas)
    state0 = load_facts(state0, ir.facts, storage_mod)

    base_origins =
      if explain do
        init_base_origins(ir.facts)
      else
        nil
      end

    {state_final, total_iterations, origins} =
      eval_strata(
        state0,
        ir.strata,
        ir.rules,
        max_iterations,
        timeout_ms,
        storage_mod,
        base_origins
      )

    duration_us = System.monotonic_time(:microsecond) - start_time

    relation_sizes =
      schemas
      |> Map.keys()
      |> Enum.map(fn name -> {name, storage_mod.size(state_final, name)} end)
      |> Map.new()

    all_rels =
      schemas
      |> Map.keys()
      |> Enum.map(fn name ->
        {name, storage_mod.stream(state_final, name) |> MapSet.new()}
      end)
      |> Map.new()

    provenance =
      if explain do
        rules_map = Map.new(ir.rules, fn r -> {r.id, r} end)

        %{
          fact_origins: origins,
          rules: rules_map
        }
      else
        nil
      end

    result = %Result{
      relations: all_rels,
      stats: %{
        iterations: total_iterations,
        duration_us: duration_us,
        relation_sizes: relation_sizes
      },
      provenance: provenance
    }

    {:ok, result}
  end

  defp init_base_origins(facts) do
    facts
    |> Enum.reduce(%{}, fn %IR.Fact{relation: rel, values: vals}, acc ->
      tuple = vals |> Enum.map(&ir_value_to_native/1) |> List.to_tuple()
      Map.update(acc, rel, %{tuple => :base}, fn m -> Map.put(m, tuple, :base) end)
    end)
  end

  defp validate_stratification(%IR{} = ir) do
    relation_strata =
      ir.strata
      |> Enum.flat_map(fn %IR.Stratum{index: idx, relations: rels} ->
        Enum.map(rels, fn rel -> {rel, idx} end)
      end)
      |> Map.new()

    fact_relations = ir.facts |> Enum.map(& &1.relation) |> Enum.uniq()

    relation_strata =
      Enum.reduce(fact_relations, relation_strata, fn rel, acc ->
        Map.put_new(acc, rel, 0)
      end)

    unstratifiable =
      Enum.filter(ir.rules, fn rule ->
        Enum.any?(negative_literals(rule), fn {:negative, %IR.Atom{relation: rel}} ->
          Map.get(relation_strata, rel, 0) >= rule.stratum
        end)
      end)

    case unstratifiable do
      [] ->
        :ok

      rules ->
        details = format_unstratifiable_details(rules)
        {:error, "unstratifiable negation detected: #{details}"}
    end
  end

  defp negative_literals(%IR.Rule{body: body}) do
    Enum.filter(body, fn
      {:negative, _} -> true
      _ -> false
    end)
  end

  defp format_unstratifiable_details(rules) do
    rules
    |> Enum.map_join("; ", fn r ->
      neg_deps =
        negative_literals(r) |> Enum.map(fn {:negative, %IR.Atom{relation: rel}} -> rel end)

      "rule #{r.id} (head: #{r.head.relation}) has unstratified negation on: #{Enum.join(neg_deps, ", ")}"
    end)
  end

  defp load_facts(state, facts, storage_mod) do
    grouped = Enum.group_by(facts, & &1.relation, & &1.values)

    Enum.reduce(grouped, state, fn {relation, values_list}, acc ->
      tuples =
        Enum.map(values_list, fn values ->
          values
          |> Enum.map(&ir_value_to_native/1)
          |> List.to_tuple()
        end)

      storage_mod.insert_many(acc, relation, tuples)
    end)
  end

  defp eval_strata(state, strata, rules, max_iterations, timeout_ms, storage_mod, base_origins) do
    Enum.reduce(strata, {state, 0, base_origins}, fn %IR.Stratum{index: stratum_idx},
                                                     {s, total_iter, origins} ->
      stratum_rules = Enum.filter(rules, fn r -> r.stratum == stratum_idx end)

      if stratum_rules == [] do
        {s, total_iter, origins}
      else
        {new_state, iters, new_origins} =
          eval_stratum(s, stratum_rules, max_iterations, timeout_ms, storage_mod, origins)

        {new_state, total_iter + iters, new_origins}
      end
    end)
  end

  defp eval_stratum(state, rules, max_iterations, timeout_ms, storage_mod, origins) do
    all_rels = all_relation_names(rules)
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    full = snapshot_facts(state, all_rels, storage_mod)
    delta = full
    old = empty_facts(all_rels)

    ctx = %{
      state: state,
      rules: rules,
      full: full,
      delta: delta,
      old: old,
      all_rels: all_rels,
      iteration: 0,
      max_iterations: max_iterations,
      deadline: deadline,
      storage_mod: storage_mod,
      origins: origins
    }

    ctx = fixpoint(ctx)

    {ctx.state, ctx.iteration, ctx.origins}
  end

  defp fixpoint(%{iteration: iter, max_iterations: max} = ctx) when iter >= max do
    ctx
  end

  defp fixpoint(ctx) do
    if System.monotonic_time(:millisecond) > ctx.deadline do
      ctx
    else
      if delta_empty?(ctx.delta, ctx.all_rels) do
        ctx
      else
        iterate(ctx)
      end
    end
  end

  defp iterate(ctx) do
    derived_all = derive_all(ctx.rules, ctx.full, ctx.delta, ctx.old)
    new_tuples = filter_new(derived_all, ctx.full)

    if all_mapsets_empty?(new_tuples) do
      ctx
    else
      derived_origins = derive_origins(ctx.rules, ctx.full, ctx.delta, ctx.old)
      origins = merge_origins(ctx.origins, derived_origins)

      state = insert_new(ctx.state, new_tuples, ctx.storage_mod)
      old = ctx.full
      full = snapshot_facts(state, ctx.all_rels, ctx.storage_mod)
      delta = compute_delta(full, old, ctx.all_rels)

      fixpoint(%{
        ctx
        | state: state,
          full: full,
          delta: delta,
          old: old,
          iteration: ctx.iteration + 1,
          origins: origins
      })
    end
  end

  defp derive_all(rules, full, delta, old) do
    rules
    |> Enum.flat_map(fn rule ->
      head_rel = rule.head.relation

      Evaluator.eval_rule_iteration(rule, full, delta, old)
      |> Enum.map(fn tuple -> {head_rel, tuple} end)
    end)
    |> Enum.group_by(fn {rel, _tuple} -> rel end, fn {_rel, tuple} -> tuple end)
    |> Enum.map(fn {rel, tuples} -> {rel, MapSet.new(Enum.uniq(tuples))} end)
    |> Map.new()
  end

  defp derive_origins(rules, full, delta, old) do
    rules
    |> Enum.flat_map(fn rule ->
      head_rel = rule.head.relation

      Evaluator.eval_rule_iteration(rule, full, delta, old)
      |> Enum.map(fn tuple -> {head_rel, tuple, rule.id} end)
    end)
    |> Enum.reduce(%{}, fn {rel, tuple, rule_id}, acc ->
      Map.update(acc, rel, %{tuple => rule_id}, fn m -> Map.put(m, tuple, rule_id) end)
    end)
  end

  defp merge_origins(existing, new) do
    Map.merge(existing || %{}, new, fn _rel, left, right ->
      Map.merge(left, right)
    end)
  end

  defp filter_new(derived, full) do
    Map.new(derived, fn {rel, tuples} ->
      existing = Map.get(full, rel, MapSet.new())
      {rel, MapSet.difference(tuples, existing)}
    end)
  end

  defp insert_new(state, new_tuples, storage_mod) do
    Enum.reduce(new_tuples, state, fn {rel, tuples}, acc ->
      Enum.reduce(MapSet.to_list(tuples), acc, fn tuple, s_acc ->
        storage_mod.insert(s_acc, rel, tuple)
      end)
    end)
  end

  defp compute_delta(full, old, all_rels) do
    Enum.reduce(all_rels, %{}, fn rel, acc ->
      full_set = Map.get(full, rel, MapSet.new())
      old_set = Map.get(old, rel, MapSet.new())
      Map.put(acc, rel, MapSet.difference(full_set, old_set))
    end)
  end

  defp snapshot_facts(state, relations, storage_mod) do
    Enum.reduce(relations, %{}, fn rel, acc ->
      Map.put(acc, rel, storage_mod.stream(state, rel) |> MapSet.new())
    end)
  end

  defp empty_facts(relations) do
    Enum.reduce(relations, %{}, fn rel, acc ->
      Map.put(acc, rel, MapSet.new())
    end)
  end

  defp delta_empty?(delta, all_rels) do
    Enum.all?(all_rels, fn rel ->
      Map.get(delta, rel, MapSet.new()) |> MapSet.size() == 0
    end)
  end

  defp all_mapsets_empty?(map) do
    Enum.all?(map, fn {_rel, set} -> MapSet.size(set) == 0 end)
  end

  defp all_relation_names(rules) do
    rules
    |> Enum.flat_map(fn r -> [r.head.relation | body_relations(r)] end)
    |> Enum.uniq()
  end

  defp body_relations(rule) do
    rule.body
    |> Enum.flat_map(fn
      {:positive, %IR.Atom{relation: r}} -> [r]
      {:negative, %IR.Atom{relation: r}} -> [r]
      {:constraint, _} -> []
    end)
    |> Enum.uniq()
  end

  defp ir_value_to_native({:int, n}), do: n
  defp ir_value_to_native({:str, s}), do: s
  defp ir_value_to_native({:atom, a}), do: a
end
