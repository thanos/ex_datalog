defmodule ExDatalog.RuntimeFactsTest do
  use ExUnit.Case, async: true

  alias ExDatalog.{Knowledge, Program}

  describe "Schema relation constructors" do
    test "constructor returns {relation, values} tuple" do
      defmodule EmpSchema do
        use ExDatalog.Schema

        relation :emp do
          field(:name, :atom)
          field(:dept, :atom)
        end

        relation :dept_count do
          field(:dept, :atom)
          field(:n, :integer)
        end

        rule dept_count(D, N) do
          emp(E, D)
          count(E, N)
        end
      end

      assert EmpSchema.emp(:alice, :eng) == {"emp", [:alice, :eng]}
      assert EmpSchema.dept_count(:eng, 3) == {"dept_count", [:eng, 3]}
    end
  end

  describe "Schema.new/0" do
    test "returns a blank program with no facts" do
      defmodule BlankSchema do
        use ExDatalog.Schema

        relation :edge do
          field(:from, :atom)
          field(:to, :atom)
        end

        relation :path do
          field(:from, :atom)
          field(:to, :atom)
        end

        rule path(X, Y) do
          edge(X, Y)
        end
      end

      prog = BlankSchema.new()
      assert prog.facts == []
      assert Map.has_key?(prog.relations, "edge")
      assert Map.has_key?(prog.relations, "path")
    end

    test "new/0 excludes compile-time facts; program/0 includes them" do
      defmodule AxiomSchema do
        use ExDatalog.Schema

        relation :edge do
          field(:from, :atom)
          field(:to, :atom)
        end

        fact(edge(:a, :b))

        rule edge(X, Y) do
          edge(X, Y)
        end
      end

      blank = AxiomSchema.new()
      assert blank.facts == []

      with_axioms = AxiomSchema.program()
      assert {"edge", [:a, :b]} in with_axioms.facts
    end
  end

  describe "Program.add_fact/2 (tuple form)" do
    test "adds a fact from a {relation, values} tuple" do
      prog =
        Program.new()
        |> Program.add_relation("emp", [:atom, :atom])
        |> Program.add_fact({"emp", [:alice, :eng]})

      assert {"emp", [:alice, :eng]} in prog.facts
    end

    test "pipeable with schema constructors" do
      defmodule PipeSchema do
        use ExDatalog.Schema

        relation :edge do
          field(:from, :atom)
          field(:to, :atom)
        end

        relation :path do
          field(:from, :atom)
          field(:to, :atom)
        end

        rule path(X, Y) do
          edge(X, Y)
        end

        rule path(X, Z) do
          edge(X, Y)
          path(Y, Z)
        end
      end

      {:ok, k} =
        PipeSchema.new()
        |> Program.add_fact(PipeSchema.edge(:a, :b))
        |> Program.add_fact(PipeSchema.edge(:b, :c))
        |> Program.materialize()

      result = Knowledge.get(k, "path") |> MapSet.to_list() |> Enum.sort()
      assert {:a, :b} in result
      assert {:b, :c} in result
      assert {:a, :c} in result
    end

    test "returns error for unknown relation" do
      prog = Program.new() |> Program.add_relation("emp", [:atom, :atom])
      assert {:error, _} = Program.add_fact(prog, {"unknown", [:x]})
    end

    test "returns error for arity mismatch" do
      prog = Program.new() |> Program.add_relation("emp", [:atom, :atom])
      assert {:error, _} = Program.add_fact(prog, {"emp", [:only_one]})
    end
  end

  describe "Program.add_facts/2" do
    test "adds multiple facts at once" do
      prog =
        Program.new()
        |> Program.add_relation("emp", [:atom, :atom])
        |> Program.add_facts([
          {"emp", [:alice, :eng]},
          {"emp", [:bob, :eng]},
          {"emp", [:carol, :ops]}
        ])

      assert length(prog.facts) == 3
    end

    test "stops on first error" do
      prog = Program.new() |> Program.add_relation("emp", [:atom, :atom])

      assert {:error, _} =
               Program.add_facts(prog, [
                 {"emp", [:alice, :eng]},
                 {"unknown", [:x]},
                 {"emp", [:bob, :eng]}
               ])
    end

    test "returns error and does not modify original program on failure" do
      prog = Program.new() |> Program.add_relation("emp", [:atom, :atom])

      result = Program.add_facts(prog, [{"emp", [:alice, :eng]}, {"unknown", [:x]}])

      assert {:error, _} = result
      assert prog.facts == []
    end

    test "propagates error through pipe chain" do
      prog = Program.new() |> Program.add_relation("emp", [:atom, :atom])

      result =
        prog
        |> Program.add_facts([{"unknown", [:x]}])
        |> Program.add_fact({"emp", [:alice, :eng]})
        |> Program.materialize()

      assert {:error, _} = result
    end

    test "handles empty list" do
      prog = Program.new() |> Program.add_relation("emp", [:atom, :atom])
      result = Program.add_facts(prog, [])
      assert result.facts == []
    end

    test "pipeable with schema constructors" do
      defmodule BulkSchema do
        use ExDatalog.Schema

        relation :emp do
          field(:name, :atom)
          field(:dept, :atom)
        end

        relation :dept_count do
          field(:dept, :atom)
          field(:n, :integer)
        end

        rule dept_count(D, N) do
          emp(E, D)
          count(E, N)
        end
      end

      {:ok, k} =
        BulkSchema.new()
        |> Program.add_facts([
          BulkSchema.emp(:alice, :eng),
          BulkSchema.emp(:bob, :eng),
          BulkSchema.emp(:carol, :ops),
          BulkSchema.emp(:dave, :eng),
          BulkSchema.emp(:eve, :ops)
        ])
        |> Program.materialize()

      result = Knowledge.get(k, "dept_count") |> MapSet.to_list() |> MapSet.new()
      assert {:eng, 3} in result
      assert {:ops, 2} in result
    end
  end

  describe "Program.materialize/1,2" do
    test "pipe-friendly materialization" do
      prog =
        Program.new()
        |> Program.add_relation("edge", [:atom, :atom])
        |> Program.add_fact("edge", [:a, :b])

      {:ok, k} = Program.materialize(prog)
      assert Knowledge.get(k, "edge") |> MapSet.size() == 1
    end

    test "passes options through" do
      defmodule MatOptsSchema do
        use ExDatalog.Schema

        relation :edge do
          field(:from, :atom)
          field(:to, :atom)
        end

        fact(edge(:a, :b))
      end

      {:ok, k} = Program.materialize(MatOptsSchema.program(), storage: ExDatalog.Storage.Map)
      assert Knowledge.get(k, "edge") |> MapSet.size() == 1
    end
  end

  describe "end-to-end: Schema.new + runtime facts + aggregates + materialize" do
    test "full runtime pipeline" do
      defmodule RuntimeDeptCount do
        use ExDatalog.Schema

        relation :emp do
          field(:name, :atom)
          field(:dept, :atom)
        end

        relation :dept_count do
          field(:dept, :atom)
          field(:n, :integer)
        end

        rule dept_count(D, N) do
          emp(E, D)
          count(E, N)
        end
      end

      {:ok, k} =
        RuntimeDeptCount.new()
        |> Program.add_facts([
          RuntimeDeptCount.emp(:alice, :eng),
          RuntimeDeptCount.emp(:bob, :eng),
          RuntimeDeptCount.emp(:carol, :ops)
        ])
        |> Program.materialize()

      result = Knowledge.get(k, "dept_count") |> MapSet.to_list() |> Enum.sort()
      assert {:eng, 2} in result
      assert {:ops, 1} in result
    end

    test "mixing compile-time facts with runtime facts" do
      defmodule MixedSchema do
        use ExDatalog.Schema

        relation :edge do
          field(:from, :atom)
          field(:to, :atom)
        end

        relation :path do
          field(:from, :atom)
          field(:to, :atom)
        end

        fact(edge(:a, :b))

        rule path(X, Y) do
          edge(X, Y)
        end

        rule path(X, Z) do
          edge(X, Y)
          path(Y, Z)
        end
      end

      # program() includes compile-time fact :a→:b
      prog = MixedSchema.program()
      # Add runtime facts
      prog = Program.add_fact(prog, MixedSchema.edge(:b, :c))
      prog = Program.add_fact(prog, MixedSchema.edge(:c, :d))

      {:ok, k} = Program.materialize(prog)
      result = Knowledge.get(k, "path") |> MapSet.to_list() |> Enum.sort()
      assert {:a, :b} in result
      assert {:b, :c} in result
      assert {:c, :d} in result
      assert {:a, :c} in result
      assert {:a, :d} in result
      assert {:b, :d} in result
    end
  end
end
