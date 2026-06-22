defmodule ExDatalog.Constraints.BeamCallback do
  @moduledoc """
  Evaluation of BEAM callback predicates.

  A callback applies an Elixir function to argument values resolved (by variable
  name) from the current binding. The function must be deterministic and
  side-effect free — these are caller contracts, not enforced.

  The engine enforces only:

  - **Timeout** — the call runs in a `Task` with a configurable timeout
    (`:callback_timeout_ms`, default 100ms). A timeout filters the binding.
  - **Exception isolation** — a raised exception filters the binding.

  Boolean callbacks (`result: nil`) act as filters: `true` keeps the binding,
  `false`/timeout/exception drops it. Value-returning callbacks
  (`result: {:var, name}`) bind the return value to `name`.
  """

  alias ExDatalog.IR

  @default_timeout_ms 100

  @doc """
  Applies a callback against a binding.

  Returns `{:ok, binding}` (boolean true, or value bound) or `:filter`
  (boolean false, unbound argument, timeout, or exception).
  """
  @spec apply_callback(IR.Callback.t(), map(), keyword()) :: {:ok, map()} | :filter
  def apply_callback(
        %IR.Callback{module: m, function: f, args: arg_terms, result: result},
        binding,
        opts
      ) do
    case resolve_args(arg_terms, binding) do
      {:ok, args} ->
        timeout = Keyword.get(opts, :callback_timeout_ms, @default_timeout_ms)

        case safe_apply(m, f, args, timeout) do
          {:ok, true} when result == nil -> {:ok, binding}
          {:ok, false} when result == nil -> :filter
          {:ok, value} when result != nil -> {:ok, bind_result(binding, result, value)}
          {:ok, _other} -> :filter
          {:error, _} -> :filter
        end

      :unbound ->
        :filter
    end
  end

  defp resolve_args(arg_terms, binding) do
    Enum.reduce_while(arg_terms, {:ok, []}, fn term, {:ok, acc} ->
      case IR.resolve_operand(term, binding) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        :unbound -> {:halt, :unbound}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      :unbound -> :unbound
    end
  end

  defp bind_result(binding, {:var, name}, value), do: Map.put(binding, name, value)

  # Run the callback in an unlinked, monitored process so that a raise or
  # exit inside the callback does not propagate to (or kill) the evaluator.
  # A crash or timeout is reported as `{:error, _}` and filters the binding.
  defp safe_apply(module, function, args, timeout_ms) do
    parent = self()
    ref = make_ref()

    {pid, monitor_ref} =
      spawn_monitor(fn ->
        result =
          try do
            {:ok, apply(module, function, args)}
          rescue
            e -> {:error, e}
          catch
            kind, reason -> {:error, {kind, reason}}
          end

        send(parent, {ref, result})
      end)

    receive do
      {^ref, result} ->
        Process.demonitor(monitor_ref, [:flush])
        result

      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        {:error, reason}
    after
      timeout_ms ->
        Process.exit(pid, :kill)
        Process.demonitor(monitor_ref, [:flush])
        {:error, :timeout}
    end
  end
end
