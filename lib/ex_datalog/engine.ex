defmodule ExDatalog.Engine do
  @moduledoc """
  Behaviour for pluggable Datalog evaluation backends.

  An engine takes a compiled IR program and evaluation options, then produces
  a result containing all derived facts. The default engine is
  `ExDatalog.Engine.Naive`, which implements semi-naive fixpoint evaluation.
  """

  @type ir :: ExDatalog.IR.t()
  @type opts :: keyword()
  @type reply :: {:ok, ExDatalog.Result.t()} | {:error, term()}

  @callback evaluate(ir, opts) :: reply
  @callback name() :: String.t()
end
