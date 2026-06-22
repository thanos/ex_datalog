defmodule ExDatalog.Planner.Join do
  @moduledoc """
  A planned join: one positive body atom position within a rule.

  `position` is the 0-based index of the atom within the rule's positive body.
  `delta_position` indicates the semi-naive delta slot when applicable, or
  `nil`. `strategy` records how the join is executed; the default engine uses
  `:nested_loop`.
  """

  @enforce_keys [:relation, :position]
  defstruct [:relation, :position, delta_position: nil, strategy: :nested_loop]

  @type strategy :: :nested_loop | :indexed

  @type t :: %__MODULE__{
          relation: String.t(),
          position: non_neg_integer(),
          delta_position: non_neg_integer() | nil,
          strategy: strategy()
        }
end
