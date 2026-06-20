defmodule ExDatalog.Storage.ETSConformanceExtraTest do
  use ExUnit.Case, async: true

  alias ExDatalog.Storage.ETS

  @schemas %{
    "parent" => %{arity: 2, types: [:atom, :atom]},
    "ancestor" => %{arity: 2, types: [:atom, :atom]},
    "value" => %{arity: 2, types: [:atom, :integer]}
  }

  describe "build_index/3 and get_indexed/4" do
    test "builds single-column index and retrieves matching tuples" do
      state = ETS.init(@schemas)
      state = ETS.insert_many(state, "parent", [{:alice, :bob}, {:carol, :dave}, {:alice, :carol}])
      state = ETS.build_index(state, "parent", [0])
      result = ETS.get_indexed(state, "parent", [0], {:alice})
      assert length(result) == 2
      assert {:alice, :bob} in result
      assert {:alice, :carol} in result
      ETS.teardown(state)
    end

    test "builds multi-column index and retrieves matching tuples" do
      state = ETS.init(@schemas)
      state = ETS.insert_many(state, "parent", [{:alice, :bob}, {:carol, :dave}, {:alice, :carol}])
      state = ETS.build_index(state, "parent", [0, 1])
      result = ETS.get_indexed(state, "parent", [0, 1], {:alice, :bob})
      assert result == [{:alice, :bob}]
      ETS.teardown(state)
    end

    test "returns empty list for non-matching key" do
      state = ETS.init(@schemas)
      state = ETS.insert(state, "parent", {:alice, :bob})
      state = ETS.build_index(state, "parent", [0])
      result = ETS.get_indexed(state, "parent", [0], {:nonexistent})
      assert result == []
      ETS.teardown(state)
    end

    test "returns empty list if index not built" do
      state = ETS.init(@schemas)
      state = ETS.insert(state, "parent", {:alice, :bob})
      result = ETS.get_indexed(state, "parent", [0], {:alice})
      assert result == []
      ETS.teardown(state)
    end

    test "raises ArgumentError for unknown relation" do
      state = ETS.init(@schemas)
      assert_raise ArgumentError, ~r/unknown relation/, fn ->
        ETS.build_index(state, "nonexistent", [0])
      end
      ETS.teardown(state)
    end
  end

  describe "update_index/4" do
    test "incrementally updates existing index with delta tuples" do
      state = ETS.init(@schemas)
      state = ETS.insert_many(state, "parent", [{:alice, :bob}, {:carol, :dave}])
      state = ETS.build_index(state, "parent", [0])
      state = ETS.insert(state, "parent", {:alice, :eve})
      state = ETS.update_index(state, "parent", [0], [{:alice, :eve}])
      result = ETS.get_indexed(state, "parent", [0], {:alice})
      assert length(result) == 2
      assert {:alice, :bob} in result
      assert {:alice, :eve} in result
      ETS.teardown(state)
    end

    test "builds index on the fly if not yet built" do
      state = ETS.init(@schemas)
      state = ETS.insert_many(state, "parent", [{:alice, :bob}])
      state = ETS.update_index(state, "parent", [0], [{:carol, :dave}])
      result = ETS.get_indexed(state, "parent", [0], {:carol})
      assert result == [{:carol, :dave}]
      ETS.teardown(state)
    end

    test "raises ArgumentError for unknown relation" do
      state = ETS.init(@schemas)
      assert_raise ArgumentError, ~r/unknown relation/, fn ->
        ETS.update_index(state, "nonexistent", [0], [{:a, :b}])
      end
      ETS.teardown(state)
    end
  end

  describe "edge cases" do
    test "size returns 0 for unknown relation" do
      state = ETS.init(@schemas)
      assert ETS.size(state, "nonexistent") == 0
      ETS.teardown(state)
    end

    test "stream returns [] for unknown relation" do
      state = ETS.init(@schemas)
      assert ETS.stream(state, "nonexistent") == []
      ETS.teardown(state)
    end

    test "member? returns false for unknown relation" do
      state = ETS.init(@schemas)
      refute ETS.member?(state, "nonexistent", {:a, :b})
      ETS.teardown(state)
    end

    test "insert raises ArgumentError for unknown relation" do
      state = ETS.init(@schemas)
      assert_raise ArgumentError, ~r/unknown relation/, fn ->
        ETS.insert(state, "nonexistent", {:a, :b})
      end
      ETS.teardown(state)
    end

    test "insert_many raises ArgumentError for unknown relation" do
      state = ETS.init(@schemas)
      assert_raise ArgumentError, ~r/unknown relation/, fn ->
        ETS.insert_many(state, "nonexistent", [{:a, :b}])
      end
      ETS.teardown(state)
    end

    test "relations returns sorted list of all relation names" do
      state = ETS.init(@schemas)
      assert ETS.relations(state) == ["ancestor", "parent", "value"]
      ETS.teardown(state)
    end
  end

  describe "init/2 options" do
    test "write_concurrency option is stored" do
      state = ETS.init(@schemas, write_concurrency: true)
      assert state.options[:write_concurrency] == true
      ETS.teardown(state)
    end

    test "read_concurrency defaults to true when access is public" do
      state = ETS.init(@schemas, access: :public)
      assert state.options[:read_concurrency] == true
      assert state.options[:access] == :public
      ETS.teardown(state)
    end
  end
end
