defmodule ExDatalog.Storage.BackendConformance do
  @moduledoc """
  Shared conformance tests for Storage backends.

  Any module implementing `ExDatalog.Storage` must pass all tests defined
  by `backend_conformance_tests/1`. Use in your test module:

      defmodule ExDatalog.Storage.MapConformanceTest do
        use ExUnit.Case, async: true
        import ExDatalog.Storage.BackendConformance

        backend_conformance_tests(ExDatalog.Storage.Map)
      end
  """

  alias ExDatalog.Capabilities
  alias ExDatalog.Storage.BackendConformance

  @schemas %{
    "parent" => %{arity: 2, types: [:atom, :atom]},
    "ancestor" => %{arity: 2, types: [:atom, :atom]},
    "value" => %{arity: 2, types: [:atom, :integer]}
  }

  @doc """
  Returns the shared schemas used by conformance tests.
  """
  def schemas, do: @schemas

  defmacro backend_conformance_tests(backend) do
    quote do
      alias unquote(backend), as: B

      @schemas ExDatalog.Storage.BackendConformance.schemas()

      BackendConformance.__init_tests__(B, @schemas)
      BackendConformance.__insert_member_tests__(B, @schemas)
      BackendConformance.__insert_many_tests__(B, @schemas)
      BackendConformance.__stream_tests__(B, @schemas)
      BackendConformance.__size_tests__(B, @schemas)
      BackendConformance.__index_tests__(B, @schemas)
      BackendConformance.__update_index_tests__(B, @schemas)
      BackendConformance.__relations_tests__(B, @schemas)
      BackendConformance.__capabilities_tests__(B, @schemas)
      BackendConformance.__teardown_tests__(B, @schemas)
      BackendConformance.__consistency_tests__(B, @schemas)
    end
  end

  defmacro __init_tests__(backend, schemas) do
    quote do
      describe "init/1" do
        test "creates empty storage with all relation schemas" do
          state = unquote(backend).init(unquote(schemas))
          assert unquote(backend).relations(state) == ["ancestor", "parent", "value"]
          assert unquote(backend).size(state, "parent") == 0
          assert unquote(backend).size(state, "ancestor") == 0
          assert unquote(backend).size(state, "value") == 0
        end
      end
    end
  end

  defmacro __insert_member_tests__(backend, schemas) do
    quote do
      describe "insert/3 and member?/3" do
        test "inserts a tuple and reports membership" do
          state = unquote(backend).init(unquote(schemas))
          state = unquote(backend).insert(state, "parent", {:alice, :bob})
          assert unquote(backend).member?(state, "parent", {:alice, :bob})
          refute unquote(backend).member?(state, "parent", {:alice, :carol})
          refute unquote(backend).member?(state, "parent", {:bob, :alice})
        end

        test "insert is idempotent" do
          state = unquote(backend).init(unquote(schemas))
          state = unquote(backend).insert(state, "parent", {:alice, :bob})
          state = unquote(backend).insert(state, "parent", {:alice, :bob})
          assert unquote(backend).size(state, "parent") == 1
        end

        test "inserts into different relations independently" do
          state = unquote(backend).init(unquote(schemas))
          state = unquote(backend).insert(state, "parent", {:alice, :bob})
          state = unquote(backend).insert(state, "ancestor", {:alice, :carol})
          assert unquote(backend).size(state, "parent") == 1
          assert unquote(backend).size(state, "ancestor") == 1
        end

        test "member? returns false for unknown relation" do
          state = unquote(backend).init(unquote(schemas))
          refute unquote(backend).member?(state, "nonexistent", {:a, :b})
        end
      end
    end
  end

  defmacro __insert_many_tests__(backend, schemas) do
    quote do
      describe "insert_many/3" do
        test "inserts multiple tuples at once" do
          state = unquote(backend).init(unquote(schemas))
          state = unquote(backend).insert_many(state, "parent", [{:alice, :bob}, {:carol, :dave}])
          assert unquote(backend).size(state, "parent") == 2
          assert unquote(backend).member?(state, "parent", {:alice, :bob})
          assert unquote(backend).member?(state, "parent", {:carol, :dave})
        end

        test "insert_many is idempotent" do
          state = unquote(backend).init(unquote(schemas))
          state = unquote(backend).insert_many(state, "parent", [{:alice, :bob}, {:alice, :bob}])
          assert unquote(backend).size(state, "parent") == 1
        end
      end
    end
  end

  defmacro __stream_tests__(backend, schemas) do
    quote do
      describe "stream/2" do
        test "returns all tuples for a relation in sorted order" do
          state = unquote(backend).init(unquote(schemas))
          state = unquote(backend).insert_many(state, "parent", [{:alice, :bob}, {:carol, :dave}])
          tuples = unquote(backend).stream(state, "parent")
          assert length(tuples) == 2
          assert {:alice, :bob} in tuples
          assert {:carol, :dave} in tuples
        end

        test "returns empty list for empty relation" do
          state = unquote(backend).init(unquote(schemas))
          assert unquote(backend).stream(state, "parent") == []
        end

        test "returns deterministically sorted output" do
          state = unquote(backend).init(unquote(schemas))
          tuples = [{:z, :a}, {:a, :z}, {:m, :m}]
          state = unquote(backend).insert_many(state, "parent", tuples)
          result = unquote(backend).stream(state, "parent")
          assert result == Enum.sort(tuples)
        end

        test "returns deterministically sorted output regardless of insertion order" do
          state = unquote(backend).init(unquote(schemas))
          state = unquote(backend).insert(state, "parent", {:z, :a})
          state = unquote(backend).insert(state, "parent", {:a, :z})
          state = unquote(backend).insert(state, "parent", {:m, :m})
          result1 = unquote(backend).stream(state, "parent")

          state2 = unquote(backend).init(unquote(schemas))
          state2 = unquote(backend).insert(state2, "parent", {:a, :z})
          state2 = unquote(backend).insert(state2, "parent", {:m, :m})
          state2 = unquote(backend).insert(state2, "parent", {:z, :a})
          result2 = unquote(backend).stream(state2, "parent")

          assert result1 == result2
        end
      end
    end
  end

  defmacro __size_tests__(backend, schemas) do
    quote do
      describe "size/2" do
        test "returns correct count" do
          state = unquote(backend).init(unquote(schemas))
          assert unquote(backend).size(state, "parent") == 0
          state = unquote(backend).insert_many(state, "parent", [{:a, :b}, {:c, :d}, {:e, :f}])
          assert unquote(backend).size(state, "parent") == 3
        end

        test "returns 0 for unknown relation" do
          state = unquote(backend).init(unquote(schemas))
          assert unquote(backend).size(state, "nonexistent") == 0
        end
      end
    end
  end

  defmacro __index_tests__(backend, schemas) do
    quote do
      describe "build_index/3 and get_indexed/4" do
        test "builds single-column index and retrieves matching tuples" do
          state = unquote(backend).init(unquote(schemas))

          state =
            unquote(backend).insert_many(state, "parent", [
              {:alice, :bob},
              {:carol, :dave},
              {:alice, :carol}
            ])

          state = unquote(backend).build_index(state, "parent", [0])
          result = unquote(backend).get_indexed(state, "parent", [0], {:alice})
          assert length(result) == 2
          assert {:alice, :bob} in result
          assert {:alice, :carol} in result
        end

        test "builds multi-column index and retrieves matching tuples" do
          state = unquote(backend).init(unquote(schemas))

          state =
            unquote(backend).insert_many(state, "parent", [
              {:alice, :bob},
              {:carol, :dave},
              {:alice, :carol}
            ])

          state = unquote(backend).build_index(state, "parent", [0, 1])
          result = unquote(backend).get_indexed(state, "parent", [0, 1], {:alice, :bob})
          assert result == [{:alice, :bob}]
        end

        test "returns empty list for non-matching key" do
          state = unquote(backend).init(unquote(schemas))
          state = unquote(backend).insert(state, "parent", {:alice, :bob})
          state = unquote(backend).build_index(state, "parent", [0])
          result = unquote(backend).get_indexed(state, "parent", [0], {:nonexistent})
          assert result == []
        end

        test "returns empty list if index not built" do
          state = unquote(backend).init(unquote(schemas))
          state = unquote(backend).insert(state, "parent", {:alice, :bob})
          result = unquote(backend).get_indexed(state, "parent", [0], {:alice})
          assert result == []
        end
      end
    end
  end

  defmacro __update_index_tests__(backend, schemas) do
    quote do
      describe "update_index/4" do
        test "incrementally updates index with delta tuples" do
          state = unquote(backend).init(unquote(schemas))
          state = unquote(backend).insert_many(state, "parent", [{:alice, :bob}, {:carol, :dave}])
          state = unquote(backend).build_index(state, "parent", [0])

          state = unquote(backend).insert(state, "parent", {:alice, :eve})
          state = unquote(backend).update_index(state, "parent", [0], [{:alice, :eve}])

          result = unquote(backend).get_indexed(state, "parent", [0], {:alice})
          assert length(result) == 2
          assert {:alice, :bob} in result
          assert {:alice, :eve} in result
        end

        test "builds index on the fly if not yet built" do
          state = unquote(backend).init(unquote(schemas))
          state = unquote(backend).insert_many(state, "parent", [{:alice, :bob}])
          state = unquote(backend).update_index(state, "parent", [0], [{:carol, :dave}])
          result = unquote(backend).get_indexed(state, "parent", [0], {:carol})
          assert result == [{:carol, :dave}]
        end
      end
    end
  end

  defmacro __relations_tests__(backend, schemas) do
    quote do
      describe "relations/1" do
        test "returns sorted list of all relation names" do
          state = unquote(backend).init(unquote(schemas))
          assert unquote(backend).relations(state) == ["ancestor", "parent", "value"]
        end
      end
    end
  end

  defmacro __capabilities_tests__(backend, schemas) do
    quote do
      describe "capabilities/1" do
        test "returns a Capabilities struct" do
          state = unquote(backend).init(unquote(schemas))
          caps = unquote(backend).capabilities(state)
          assert %Capabilities{} = caps
        end

        test "reports a valid storage type" do
          state = unquote(backend).init(unquote(schemas))
          caps = unquote(backend).capabilities(state)
          assert caps.storage_type in [:map, :ets, :external]
        end

        test "reports arithmetic and comparison constraints support" do
          state = unquote(backend).init(unquote(schemas))
          caps = unquote(backend).capabilities(state)
          assert caps.arithmetic_constraints == true
          assert caps.comparison_constraints == true
        end
      end
    end
  end

  defmacro __teardown_tests__(backend, schemas) do
    quote do
      describe "teardown/1" do
        test "returns :ok" do
          state = unquote(backend).init(unquote(schemas))
          assert unquote(backend).teardown(state) == :ok
        end
      end
    end
  end

  defmacro __consistency_tests__(backend, schemas) do
    quote do
      describe "cross-operation consistency" do
        test "size tracks insertions" do
          state = unquote(backend).init(unquote(schemas))
          assert unquote(backend).size(state, "parent") == 0
          state = unquote(backend).insert(state, "parent", {:a, :b})
          assert unquote(backend).size(state, "parent") == 1
          state = unquote(backend).insert(state, "parent", {:c, :d})
          assert unquote(backend).size(state, "parent") == 2
          state = unquote(backend).insert(state, "parent", {:a, :b})
          assert unquote(backend).size(state, "parent") == 2
        end

        test "member? consistency with size" do
          state = unquote(backend).init(unquote(schemas))
          state = unquote(backend).insert_many(state, "parent", [{:a, :b}, {:c, :d}])
          assert unquote(backend).size(state, "parent") == 2
          assert unquote(backend).member?(state, "parent", {:a, :b})
          assert unquote(backend).member?(state, "parent", {:c, :d})
          refute unquote(backend).member?(state, "parent", {:x, :y})
        end

        test "stream consistency with member?" do
          state = unquote(backend).init(unquote(schemas))
          state = unquote(backend).insert_many(state, "parent", [{:a, :b}, {:c, :d}, {:e, :f}])
          tuples = unquote(backend).stream(state, "parent")
          assert length(tuples) == 3

          for tuple <- tuples do
            assert unquote(backend).member?(state, "parent", tuple)
          end
        end
      end
    end
  end
end
