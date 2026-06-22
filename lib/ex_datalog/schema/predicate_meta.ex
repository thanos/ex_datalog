defmodule ExDatalog.Schema.PredicateMeta do
  @moduledoc """
  Metadata for a callback predicate declared with the `predicate/5` macro.

  Records the DSL name, the target module/function, the declared argument
  types, and the return type (`:boolean` for filters, `:value` for
  value-returning callbacks).
  """

  @enforce_keys [:name, :module, :function, :arg_types, :return_type]
  defstruct [:name, :module, :function, :arg_types, :return_type]

  @type return_type :: :boolean | :value

  @type t :: %__MODULE__{
          name: atom(),
          module: module(),
          function: atom(),
          arg_types: [atom()],
          return_type: return_type()
        }
end
