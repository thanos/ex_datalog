defmodule ExDatalog.Storage.MapTest do
  use ExUnit.Case, async: true

  alias ExDatalog.Storage.Map

  @schemas %{
    "parent" => %{arity: 2, types: [:atom, :atom]},
    "ancestor" => %{arity: 2, types: [:atom, :atom]},
    "value" => %{arity: 2, types: [:atom, :integer]}
  }

  describe "init/1" do
    test "creates empty storage with all relation schemas" do
      state = Map.init(@schemas)
      assert Map.relations(state) == ["ancestor", "parent", "value"]
      assert Map.size(state, "parent") == 0
      assert Map.size(state, "ancestor") == 0
    end
  end

  describe "insert/3 and member?/3" do
    test "inserts a tuple and reports membership" do
      state = Map.init(@schemas)
      state = Map.insert(state, "parent", {:alice, :bob})
      assert Map.member?(state, "parent", {:alice, :bob})
      refute Map.member?(state, "parent", {:alice, :carol})
      refute Map.member?(state, "parent", {:bob, :alice})
    end

    test "insert is idempotent" do
      state = Map.init(@schemas)
      state = Map.insert(state, "parent", {:alice, :bob})
      state = Map.insert(state, "parent", {:alice, :bob})
      assert Map.size(state, "parent") == 1
    end

    test "inserts into different relations independently" do
      state = Map.init(@schemas)
      state = Map.insert(state, "parent", {:alice, :bob})
      state = Map.insert(state, "ancestor", {:alice, :carol})
      assert Map.size(state, "parent") == 1
      assert Map.size(state, "ancestor") == 1
    end
  end

  describe "insert_many/3" do
    test "inserts multiple tuples at once" do
      state = Map.init(@schemas)
      state = Map.insert_many(state, "parent", [{:alice, :bob}, {:carol, :dave}])
      assert Map.size(state, "parent") == 2
      assert Map.member?(state, "parent", {:alice, :bob})
      assert Map.member?(state, "parent", {:carol, :dave})
    end

    test "insert_many is idempotent" do
      state = Map.init(@schemas)
      state = Map.insert_many(state, "parent", [{:alice, :bob}, {:alice, :bob}])
      assert Map.size(state, "parent") == 1
    end
  end

  describe "stream/2" do
    test "returns all tuples for a relation" do
      state = Map.init(@schemas)
      state = Map.insert_many(state, "parent", [{:alice, :bob}, {:carol, :dave}])
      tuples = Map.stream(state, "parent")
      assert length(tuples) == 2
      assert {:alice, :bob} in tuples
      assert {:carol, :dave} in tuples
    end

    test "returns empty list for empty relation" do
      state = Map.init(@schemas)
      assert Map.stream(state, "parent") == []
    end
  end

  describe "size/2" do
    test "returns correct count" do
      state = Map.init(@schemas)
      assert Map.size(state, "parent") == 0
      state = Map.insert_many(state, "parent", [{:a, :b}, {:c, :d}, {:e, :f}])
      assert Map.size(state, "parent") == 3
    end

    test "returns 0 for unknown relation" do
      state = Map.init(@schemas)
      assert Map.size(state, "nonexistent") == 0
    end
  end

  describe "build_index/3 and get_indexed/4" do
    test "builds single-column index and retrieves matching tuples" do
      state = Map.init(@schemas)

      state =
        Map.insert_many(state, "parent", [{:alice, :bob}, {:carol, :dave}, {:alice, :carol}])

      state = Map.build_index(state, "parent", [0])
      result = Map.get_indexed(state, "parent", [0], {:alice})
      assert length(result) == 2
      assert {:alice, :bob} in result
      assert {:alice, :carol} in result
    end

    test "builds multi-column index and retrieves matching tuples" do
      state = Map.init(@schemas)

      state =
        Map.insert_many(state, "parent", [{:alice, :bob}, {:carol, :dave}, {:alice, :carol}])

      state = Map.build_index(state, "parent", [0, 1])
      result = Map.get_indexed(state, "parent", [0, 1], {:alice, :bob})
      assert result == [{:alice, :bob}]
    end

    test "returns empty list for non-matching key" do
      state = Map.init(@schemas)
      state = Map.insert(state, "parent", {:alice, :bob})
      state = Map.build_index(state, "parent", [0])
      result = Map.get_indexed(state, "parent", [0], {:nonexistent})
      assert result == []
    end

    test "returns empty list if index not built" do
      state = Map.init(@schemas)
      state = Map.insert(state, "parent", {:alice, :bob})
      result = Map.get_indexed(state, "parent", [0], {:alice})
      assert result == []
    end
  end

  describe "update_index/4" do
    test "incrementally updates index with delta tuples" do
      state = Map.init(@schemas)
      state = Map.insert_many(state, "parent", [{:alice, :bob}, {:carol, :dave}])
      state = Map.build_index(state, "parent", [0])

      state = Map.insert(state, "parent", {:alice, :eve})
      state = Map.update_index(state, "parent", [0], [{:alice, :eve}])

      result = Map.get_indexed(state, "parent", [0], {:alice})
      assert length(result) == 2
      assert {:alice, :bob} in result
      assert {:alice, :eve} in result
    end

    test "builds index on the fly if not yet built" do
      state = Map.init(@schemas)
      state = Map.insert_many(state, "parent", [{:alice, :bob}])
      state = Map.update_index(state, "parent", [0], [{:carol, :dave}])

      result = Map.get_indexed(state, "parent", [0], {:carol})
      assert result == [{:carol, :dave}]
    end
  end

  describe "relations/1" do
    test "returns sorted list of all relation names" do
      state = Map.init(@schemas)
      assert Map.relations(state) == ["ancestor", "parent", "value"]
    end
  end

  describe "member?/3" do
    test "returns false for unknown relation" do
      state = Map.init(@schemas)
      refute Map.member?(state, "nonexistent", {:a, :b})
    end
  end
end
