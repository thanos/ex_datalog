defmodule ExDatalog.Validator.Stratification do
  @moduledoc """
  Stratification checks for ExDatalog programs.

  A Datalog program with negation must be **stratifiable** — there must be
  no cycle in the dependency graph that contains a negative edge. If such a
  cycle exists, evaluation order is ambiguous and the program is rejected.

  This module:

  1. Builds a **dependency graph** from the program's rules.
  2. Computes **strongly connected components** (SCCs) using Tarjan's algorithm.
  3. Checks that **no SCC contains a negative edge**.
  4. Assigns a **stratum** to each relation.

  """

  alias ExDatalog.{Atom, Rule}
  alias ExDatalog.Validator.Error

  @compile {:no_warn_undefined, ExDatalog.Validator.Error}

  @type edge :: {String.t(), :positive | :negative}
  @type graph :: %{String.t() => [edge()]}
  @type scc :: [String.t()]

  @doc false
  @spec build_graph(ExDatalog.Program.t()) :: graph()
  def build_graph(%ExDatalog.Program{rules: rules}) do
    Enum.reduce(rules, %{}, fn rule, graph ->
      head_rel = rule.head.relation
      body_deps = body_dependencies(rule)
      current = Map.get(graph, head_rel, [])
      Map.put(graph, head_rel, Enum.uniq(current ++ body_deps))
    end)
  end

  @doc false
  @spec compute_sccs(graph()) :: [scc()]
  def compute_sccs(graph) do
    all_vertices = all_vertices(graph)

    state =
      Enum.reduce(all_vertices, initial_state(), fn v, s ->
        if Map.has_key?(s.indices, v) do
          s
        else
          {new_s, _} = strongconnect(v, graph, s)
          new_s
        end
      end)

    Enum.reverse(state.sccs)
  end

  @doc """
  Checks whether the program has unstratifiable negation.

  Returns `:ok` if all SCCs are stratifiable, or `{:error, errors}` listing
  every SCC that contains a negative edge.
  """
  @spec check(ExDatalog.Program.t()) :: :ok | {:error, [Error.t()]}
  def check(%ExDatalog.Program{} = program) do
    graph = build_graph(program)

    # Only include rules with valid body literals in the stratification check.
    # Rules with invalid body literals are caught by structural validation.
    # The graph is built from all rules; invalid rules have no body dependencies
    # added (body_dependencies/1 skips them), so they don't affect SCC computation.
    sccs = compute_sccs(graph)

    errors =
      sccs
      |> Enum.flat_map(fn scc ->
        check_scc_negation(scc, graph)
      end)

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  @doc """
  Assigns strata to all relations in the program.

  Returns a map from relation name to stratum number (0-based).
  Only valid for programs that pass `check/1`.
  """
  @spec assign_strata(ExDatalog.Program.t()) :: %{String.t() => non_neg_integer()}
  def assign_strata(%ExDatalog.Program{} = program) do
    graph = build_graph(program)
    sccs = compute_sccs(graph)
    assign_strata_greedy(graph, sccs)
  end

  @doc false
  @spec body_dependencies(Rule.t()) :: [edge()]
  def body_dependencies(%Rule{body: body}) do
    Enum.flat_map(body, fn
      {:positive, %Atom{relation: rel}} -> [{rel, :positive}]
      {:negative, %Atom{relation: rel}} -> [{rel, :negative}]
      _ -> []
    end)
  end

  # --- SCC negation check ---

  defp check_scc_negation(scc, graph) do
    scc_set = MapSet.new(scc)

    scc
    |> Enum.flat_map(fn rel ->
      deps = Map.get(graph, rel, [])

      deps
      |> Enum.filter(fn {dep, polarity} ->
        polarity == :negative and MapSet.member?(scc_set, dep)
      end)
      |> Enum.map(fn {dep, _} ->
        Error.new(
          :unstratified_negation,
          %{relation: rel, depends_on: dep, scc: Enum.sort(scc)},
          "unstratifiable negation: relation #{inspect(rel)} depends negatively " <>
            "on #{inspect(dep)} within the same SCC {#{Enum.join(Enum.sort(scc), ", ")}}"
        )
      end)
    end)
    |> Enum.uniq_by(fn e -> e.context end)
  end

  # --- Strata assignment ---

  defp assign_strata_greedy(graph, sccs) do
    all_vertices = all_vertices(graph)
    initial = Map.new(all_vertices, fn rel -> {rel, 0} end)

    Enum.reduce(sccs, initial, fn scc, strata ->
      scc_stratum = compute_scc_stratum(scc, graph, strata)
      Enum.reduce(scc, strata, fn rel, acc -> Map.put(acc, rel, scc_stratum) end)
    end)
  end

  defp compute_scc_stratum(scc, graph, current_strata) do
    scc_set = MapSet.new(scc)

    deps =
      scc
      |> Enum.flat_map(fn rel -> Map.get(graph, rel, []) end)
      |> Enum.reject(fn {dep, _} -> MapSet.member?(scc_set, dep) end)

    base_stratum =
      case deps do
        [] -> 0
        _ -> deps |> Enum.map(fn {dep, _} -> Map.get(current_strata, dep, 0) end) |> Enum.max()
      end

    has_negative_dep = Enum.any?(deps, fn {_, polarity} -> polarity == :negative end)
    if has_negative_dep, do: base_stratum + 1, else: base_stratum
  end

  # --- Tarjan's SCC algorithm ---

  defp initial_state do
    %{index: 0, stack: [], on_stack: MapSet.new(), indices: %{}, lowlinks: %{}, sccs: []}
  end

  defp all_vertices(graph) do
    heads = Map.keys(graph)
    tails = Enum.flat_map(graph, fn {_head, deps} -> Enum.map(deps, fn {rel, _} -> rel end) end)
    Enum.uniq(heads ++ tails)
  end

  defp strongconnect(v, graph, state) do
    index = state.index
    state = %{state | index: state.index + 1}
    state = put_in(state.indices[v], index)
    state = put_in(state.lowlinks[v], index)
    state = %{state | stack: [v | state.stack], on_stack: MapSet.put(state.on_stack, v)}

    neighbors = graph |> Map.get(v, []) |> Enum.map(fn {dep, _} -> dep end)

    {state, _} =
      Enum.reduce(neighbors, {state, MapSet.new()}, fn w, {s, visited} ->
        cond do
          not Map.has_key?(s.indices, w) ->
            {new_s, _} = strongconnect(w, graph, s)
            lowlink_v = min(Map.get(new_s.lowlinks, v, index), Map.get(new_s.lowlinks, w, index))
            new_s = put_in(new_s.lowlinks[v], lowlink_v)
            {new_s, MapSet.put(visited, w)}

          MapSet.member?(s.on_stack, w) ->
            lowlink_v = min(Map.get(s.lowlinks, v, index), Map.get(s.indices, w))
            {put_in(s.lowlinks[v], lowlink_v), visited}

          true ->
            {s, visited}
        end
      end)

    if state.lowlinks[v] == state.indices[v] do
      {scc, rest} = pop_until(state.stack, v)
      new_on_stack = Enum.reduce(scc, state.on_stack, &MapSet.delete(&2, &1))
      new_sccs = [Enum.reverse(scc) | state.sccs]
      {%{state | stack: rest, on_stack: new_on_stack, sccs: new_sccs}, MapSet.new()}
    else
      {state, MapSet.new()}
    end
  end

  defp pop_until([v | rest], v), do: {[v], rest}

  defp pop_until([h | t], v) do
    {popped, rest} = pop_until(t, v)
    {[h | popped], rest}
  end
end
