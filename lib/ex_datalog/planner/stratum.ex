defmodule ExDatalog.Planner.Stratum do
  @moduledoc """
  A planned stratum: the rules and relations evaluated together at one
  stratum index.

  Wraps the IR strata into a planner-friendly form that carries the actual
  `IR.Rule` structs (not just their IDs) for the engine and `explain_plan/1`.
  """

  alias ExDatalog.IR

  @enforce_keys [:index, :rules, :relations]
  defstruct [:index, :rules, :relations]

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          rules: [IR.Rule.t()],
          relations: [String.t()]
        }
end
