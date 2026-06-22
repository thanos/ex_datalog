defmodule ExDatalog.Planner.Predicate do
  @moduledoc """
  A planned predicate: a non-relational body element (constraint, aggregate,
  or callback) classified by kind.

  `kind` groups the predicate into one of the evaluation categories; `op` is
  the specific operator (e.g. `:gt`, `:count`, `:callback`). `metadata` carries
  optional details (e.g. callback module/function).
  """

  @enforce_keys [:kind, :op]
  defstruct [:kind, :op, metadata: %{}]

  @type kind ::
          :comparison
          | :arithmetic
          | :type
          | :string
          | :membership
          | :aggregate
          | :callback

  @type t :: %__MODULE__{
          kind: kind(),
          op: atom(),
          metadata: map()
        }
end
