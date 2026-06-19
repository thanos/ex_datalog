defmodule ExDatalog.Telemetry do
  @moduledoc """
  Telemetry event definitions for ExDatalog evaluation.

  All events follow `:telemetry` library conventions. Attach handlers using
  `:telemetry.attach/4` or `:telemetry.attach_many/4`.

  ## Events

  | Event | When | Measurements | Metadata |
  |---|---|---|---|
  | `[:ex_datalog, :materialize, :start]` | Before evaluation | `%{system_time: ...}` | `%{relation_count: ..., stratum_count: ...}` |
  | `[:ex_datalog, :materialize, :stop]` | After evaluation | `%{duration: ..., iterations: ...}` | `%{relation_sizes: ..., stratum_count: ..., storage_type: ...}` |
  | `[:ex_datalog, :materialize, :exception]` | On exception | `%{duration: ...}` | `%{kind: ..., reason: ..., stacktrace: ..., stratum_count: ...}` |

  The `:start` event fires before evaluation begins. The `:stop` event fires
  after evaluation completes (success or error). The `:exception` event fires
  only when an exception terminates evaluation.

  ## Zero-overhead when no handlers attached

  `:telemetry.execute/3` checks the handler table before any work, so
  unattached events are effectively free.
  """

  alias ExDatalog.IR

  @doc """
  Returns the `[:ex_datalog, :materialize, :start]` event name.
  """
  @spec materialize_start() :: [:ex_datalog | :materialize | :start, ...]
  def materialize_start, do: [:ex_datalog, :materialize, :start]

  @doc """
  Returns the `[:ex_datalog, :materialize, :stop]` event name.
  """
  @spec materialize_stop() :: [:ex_datalog | :materialize | :stop, ...]
  def materialize_stop, do: [:ex_datalog, :materialize, :stop]

  @doc """
  Returns the `[:ex_datalog, :materialize, :exception]` event name.
  """
  @spec materialize_exception() :: [:ex_datalog | :materialize | :exception, ...]
  def materialize_exception, do: [:ex_datalog, :materialize, :exception]

  @doc """
  Emits the `[:ex_datalog, :materialize, :start]` event.

  Called before evaluation begins.

  ## Measurements

  - `:system_time` — monotonic time in native units.

  ## Metadata

  - `:relation_count` — number of relations in the IR program.
  - `:stratum_count` — number of strata.
  """
  @spec emit_start(IR.t()) :: :ok
  def emit_start(%IR{} = ir) do
    :telemetry.execute(
      materialize_start(),
      %{system_time: System.monotonic_time()},
      %{relation_count: length(ir.relations), stratum_count: length(ir.strata)}
    )
  end

  @doc """
  Emits the `[:ex_datalog, :materialize, :stop]` event.

  Called after evaluation completes (success or error). The `start_time`
  argument should be the `System.monotonic_time(:microsecond)` value captured
  before evaluation started.

  ## Measurements

  - `:duration` — elapsed time in microseconds.
  - `:iterations` — total fixpoint iterations across all strata.

  ## Metadata

  - `:relation_sizes` — map of relation name to tuple count.
  - `:stratum_count` — number of strata.
  - `:storage_type` — the storage backend type (`:map`, `:ets`, or `:external`).
  """
  @spec emit_stop(
          integer(),
          non_neg_integer(),
          %{String.t() => non_neg_integer()},
          non_neg_integer(),
          atom()
        ) :: :ok
  def emit_stop(start_time, iterations, relation_sizes, stratum_count, storage_type) do
    :telemetry.execute(
      materialize_stop(),
      %{duration: System.monotonic_time(:microsecond) - start_time, iterations: iterations},
      %{relation_sizes: relation_sizes, stratum_count: stratum_count, storage_type: storage_type}
    )
  end

  @doc """
  Emits the `[:ex_datalog, :materialize, :exception]` event.

  Called when an exception terminates evaluation. The `kind`, `reason`, and
  `stacktrace` should come from `__STACKTRACE__` inside a `rescue` or `catch`.

  ## Measurements

  - `:duration` — elapsed time in microseconds before the exception.

  ## Metadata

  - `:kind` — exception kind (`:error`, `:exit`, `:throw`).
  - `:reason` — exception reason.
  - `:stacktrace` — the stacktrace.
  - `:stratum_count` — number of strata in the program.
  """
  @spec emit_exception(integer(), Exception.kind(), term(), list(), non_neg_integer()) :: :ok
  def emit_exception(start_time, kind, reason, stacktrace, stratum_count) do
    :telemetry.execute(
      materialize_exception(),
      %{duration: System.monotonic_time(:microsecond) - start_time},
      %{kind: kind, reason: reason, stacktrace: stacktrace, stratum_count: stratum_count}
    )
  end
end
