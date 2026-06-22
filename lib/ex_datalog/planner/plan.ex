defmodule ExDatalog.Planner.Plan do
  @moduledoc """
  An execution plan for a compiled IR program.

  A plan records the chosen evaluation `strategy`, the planned `strata`, the
  `joins` (one per positive body atom across all rules), and the `predicates`
  (constraints, aggregates, callbacks). The plan is descriptive: it explains
  what the engine will do without changing how the engine evaluates.

  Aggregate and callback predicates appear in `predicates` with
  `kind: :aggregate` / `kind: :callback`; there are no separate fields for them.
  """

  alias ExDatalog.Planner.{Join, Predicate, Stratum}

  @enforce_keys [:strategy, :strata]
  defstruct [:strategy, :strata, joins: [], predicates: [], metadata: %{}]

  @type strategy :: :semi_naive | :magic_sets

  @type t :: %__MODULE__{
          strategy: strategy(),
          strata: [Stratum.t()],
          joins: [Join.t()],
          predicates: [Predicate.t()],
          metadata: map()
        }
end
