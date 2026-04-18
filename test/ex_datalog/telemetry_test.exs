defmodule ExDatalog.TelemetryTest do
  use ExUnit.Case, async: false

  alias ExDatalog.{Atom, Program, Rule, Telemetry, Term}

  describe "event name functions" do
    test "query_start/0 returns the correct event name" do
      assert Telemetry.query_start() == [:ex_datalog, :query, :start]
    end

    test "query_stop/0 returns the correct event name" do
      assert Telemetry.query_stop() == [:ex_datalog, :query, :stop]
    end

    test "query_exception/0 returns the correct event name" do
      assert Telemetry.query_exception() == [:ex_datalog, :query, :exception]
    end
  end

  describe "emit_start/1" do
    test "emits start event with IR metadata" do
      {:ok, ir} =
        Program.new()
        |> Program.add_relation("edge", [:atom, :atom])
        |> Program.add_relation("path", [:atom, :atom])
        |> Program.add_rule(
          Rule.new(
            Atom.new("path", [Term.var("X"), Term.var("Y")]),
            [{:positive, Atom.new("edge", [Term.var("X"), Term.var("Y")])}]
          )
        )
        |> ExDatalog.compile()

      {measurements, metadata} =
        capture_event(Telemetry.query_start(), fn ->
          Telemetry.emit_start(ir)
        end)

      assert Map.has_key?(measurements, :system_time)
      assert metadata.relation_count == 2
      assert metadata.stratum_count == 1
    end
  end

  describe "emit_stop/4" do
    test "emits stop event with duration and iterations" do
      start_time = System.monotonic_time(:microsecond)
      relation_sizes = %{"edge" => 2}

      {measurements, metadata} =
        capture_event(Telemetry.query_stop(), fn ->
          Telemetry.emit_stop(start_time, 3, relation_sizes, 1)
        end)

      assert Map.has_key?(measurements, :duration)
      assert measurements.duration >= 0
      assert measurements.iterations == 3
      assert metadata.relation_sizes == %{"edge" => 2}
      assert metadata.stratum_count == 1
    end
  end

  describe "emit_exception/5" do
    test "emits exception event with error details" do
      start_time = System.monotonic_time(:microsecond)
      stacktrace = [{:module, :function, 1, []}]

      {measurements, metadata} =
        capture_event(Telemetry.query_exception(), fn ->
          Telemetry.emit_exception(
            start_time,
            :error,
            %RuntimeError{message: "oops"},
            stacktrace,
            2
          )
        end)

      assert Map.has_key?(measurements, :duration)
      assert measurements.duration >= 0
      assert metadata.kind == :error
      assert metadata.reason == %RuntimeError{message: "oops"}
      assert metadata.stacktrace == stacktrace
      assert metadata.stratum_count == 2
    end
  end

  describe "integration: query emits telemetry events" do
    test "successful query emits start and stop events" do
      program =
        Program.new()
        |> Program.add_relation("parent", [:atom, :atom])
        |> Program.add_relation("ancestor", [:atom, :atom])
        |> Program.add_fact("parent", [:alice, :bob])
        |> Program.add_rule(
          Rule.new(
            Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
            [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
          )
        )

      start_event =
        capture_event(Telemetry.query_start(), fn ->
          stop_event =
            capture_event(Telemetry.query_stop(), fn ->
              {:ok, _result} = ExDatalog.query(program)
            end)

          assert stop_event != nil
          {stop_measurements, stop_metadata} = stop_event
          assert stop_measurements.duration > 0
          assert stop_measurements.iterations >= 1
          assert stop_metadata.stratum_count == 1
          assert Map.has_key?(stop_metadata.relation_sizes, "parent")
        end)

      assert start_event != nil
      {_start_measurements, start_metadata} = start_event
      assert start_metadata.relation_count == 2
      assert start_metadata.stratum_count == 1
    end

    test "unstratifiable program emits start and stop with zero iterations" do
      ir = %ExDatalog.IR{
        relations: [%ExDatalog.IR.Relation{name: "p", arity: 1, types: [:atom]}],
        facts: [],
        rules: [
          %ExDatalog.IR.Rule{
            id: 0,
            head: %ExDatalog.IR.Atom{relation: "p", terms: [{:var, "X"}]},
            body: [{:negative, %ExDatalog.IR.Atom{relation: "p", terms: [{:var, "X"}]}}],
            stratum: 0,
            metadata: %{}
          }
        ],
        strata: [%ExDatalog.IR.Stratum{index: 0, rule_ids: [0], relations: ["p"]}]
      }

      start_event =
        capture_event(Telemetry.query_start(), fn ->
          stop_event =
            capture_event(Telemetry.query_stop(), fn ->
              {:error, _} = ExDatalog.evaluate(ir)
            end)

          assert stop_event != nil
          {stop_measurements, stop_metadata} = stop_event
          assert stop_measurements.iterations == 0
          assert stop_metadata.stratum_count == 1
        end)

      assert start_event != nil
    end

    test "validation failure does not emit engine telemetry" do
      program =
        Program.new()
        |> Program.add_relation("p", [:atom])
        |> Program.add_rule(
          Rule.new(
            Atom.new("p", [Term.var("X")]),
            [{:negative, Atom.new("p", [Term.var("X")])}]
          )
        )

      start_event =
        capture_event(Telemetry.query_start(), fn ->
          {:error, _} = ExDatalog.query(program)
        end)

      assert start_event == nil
    end
  end

  describe "no overhead without handlers" do
    test "query runs correctly when no telemetry handlers are attached" do
      program =
        Program.new()
        |> Program.add_relation("edge", [:atom, :atom])
        |> Program.add_fact("edge", [:a, :b])
        |> Program.add_fact("edge", [:b, :c])

      {:ok, result} = ExDatalog.query(program)
      assert MapSet.size(ExDatalog.Result.get(result, "edge")) == 2
    end
  end

  defp capture_event(event_name, fun) do
    test_pid = self()
    ref = make_ref()
    handler_id = {__MODULE__, ref}

    :telemetry.attach(
      handler_id,
      event_name,
      fn _name, measurements, metadata, _config ->
        send(test_pid, {ref, {measurements, metadata}})
      end,
      nil
    )

    fun.()

    receive do
      {^ref, event_data} ->
        :telemetry.detach(handler_id)
        event_data
    after
      1000 ->
        :telemetry.detach(handler_id)
        nil
    end
  end
end
