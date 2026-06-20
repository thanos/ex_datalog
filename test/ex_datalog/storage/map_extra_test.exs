defmodule ExDatalog.Storage.MapExtraTest do
  use ExUnit.Case, async: true

  alias ExDatalog.Storage.Map

  @schemas %{
    "parent" => %{arity: 2, types: [:atom, :atom]},
    "ancestor" => %{arity: 2, types: [:atom, :atom]}
  }

  describe "insert/3 error cases" do
    test "raises ArgumentError for unknown relation" do
      state = Map.init(@schemas)
      assert_raise ArgumentError, ~r/unknown relation/, fn ->
        Map.insert(state, "nonexistent", {:a, :b})
      end
    end
  end

  describe "insert_many/3 error cases" do
    test "raises ArgumentError for unknown relation" do
      state = Map.init(@schemas)
      assert_raise ArgumentError, ~r/unknown relation/, fn ->
        Map.insert_many(state, "nonexistent", [{:a, :b}])
      end
    end
  end

  describe "build_index/3 error cases" do
    test "raises ArgumentError for unknown relation" do
      state = Map.init(@schemas)
      assert_raise ArgumentError, ~r/unknown relation/, fn ->
        Map.build_index(state, "nonexistent", [0])
      end
    end
  end

  describe "init/2 with options" do
    test "init/2 ignores options and works" do
      state = Map.init(@schemas, some_option: true)
      assert Map.relations(state) == ["ancestor", "parent"]
    end
  end

  describe "update_index/4 error cases" do
    test "raises ArgumentError for unknown relation" do
      state = Map.init(@schemas)
      assert_raise ArgumentError, ~r/unknown relation/, fn ->
        Map.update_index(state, "nonexistent", [0], [{:a, :b}])
      end
    end
  end

  describe "stream deterministic ordering" do
    test "stream returns sorted results regardless of insertion order" do
      state = Map.init(@schemas)
      state = Map.insert(state, "parent", {:z, :a})
      state = Map.insert(state, "parent", {:m, :m})
      state = Map.insert(state, "parent", {:a, :z})
      result = Map.stream(state, "parent")
      assert result == [{:a, :z}, {:m, :m}, {:z, :a}]
    end
  end
end
