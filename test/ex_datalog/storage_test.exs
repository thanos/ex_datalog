defmodule ExDatalog.StorageTest do
  use ExUnit.Case, async: true

  alias ExDatalog.Storage

  describe "behaviour callbacks" do
    test "defines all required callbacks" do
      callbacks = Storage.behaviour_info(:callbacks)

      assert {:init, 1} in callbacks
      assert {:insert, 3} in callbacks
      assert {:insert_many, 3} in callbacks
      assert {:member?, 3} in callbacks
      assert {:size, 2} in callbacks
      assert {:stream, 2} in callbacks
      assert {:get_indexed, 4} in callbacks
      assert {:build_index, 3} in callbacks
      assert {:update_index, 4} in callbacks
      assert {:relations, 1} in callbacks
      assert {:capabilities, 1} in callbacks
      assert {:teardown, 1} in callbacks
    end
  end

  describe "implementations" do
    test "Storage.Map implements the behaviour" do
      assert Storage.Map.__info__(:attributes)[:behaviour] == [Storage]
    end

    test "Storage.ETS implements the behaviour" do
      assert Storage.ETS.__info__(:attributes)[:behaviour] == [Storage]
    end
  end

  describe "behaviour contract" do
    test "init/1 returns a state for Map backend" do
      schemas = %{"rel" => %{arity: 2, types: [:atom, :atom]}}
      state = Storage.Map.init(schemas)
      assert Storage.Map.relations(state) == ["rel"]
    end

    test "init/1 returns a state for ETS backend" do
      schemas = %{"rel" => %{arity: 2, types: [:atom, :atom]}}
      state = Storage.ETS.init(schemas)
      assert Storage.ETS.relations(state) == ["rel"]
      Storage.ETS.teardown(state)
    end

    test "capabilities/1 returns Capabilities struct for Map" do
      schemas = %{"rel" => %{arity: 2, types: [:atom, :atom]}}
      state = Storage.Map.init(schemas)
      caps = Storage.Map.capabilities(state)
      assert %ExDatalog.Capabilities{} = caps
      assert caps.storage_type == :map
    end

    test "capabilities/1 returns Capabilities struct for ETS" do
      schemas = %{"rel" => %{arity: 2, types: [:atom, :atom]}}
      state = Storage.ETS.init(schemas)
      caps = Storage.ETS.capabilities(state)
      assert %ExDatalog.Capabilities{} = caps
      assert caps.storage_type == :ets
      Storage.ETS.teardown(state)
    end

    test "teardown/1 returns :ok for Map" do
      schemas = %{"rel" => %{arity: 2, types: [:atom, :atom]}}
      state = Storage.Map.init(schemas)
      assert Storage.Map.teardown(state) == :ok
    end

    test "teardown/1 returns :ok for ETS" do
      schemas = %{"rel" => %{arity: 2, types: [:atom, :atom]}}
      state = Storage.ETS.init(schemas)
      assert Storage.ETS.teardown(state) == :ok
    end

    test "teardown/1 is idempotent for Map" do
      schemas = %{"rel" => %{arity: 2, types: [:atom, :atom]}}
      state = Storage.Map.init(schemas)
      assert Storage.Map.teardown(state) == :ok
      assert Storage.Map.teardown(state) == :ok
    end

    test "teardown/1 is idempotent for ETS" do
      schemas = %{"rel" => %{arity: 2, types: [:atom, :atom]}}
      state = Storage.ETS.init(schemas)
      assert Storage.ETS.teardown(state) == :ok
      assert Storage.ETS.teardown(state) == :ok
    end
  end

  describe "cross-backend parity" do
    setup do
      schemas = %{
        "rel" => %{arity: 2, types: [:atom, :atom]},
        "val" => %{arity: 2, types: [:atom, :integer]}
      }

      tuples = [{:a, :b}, {:c, :d}, {:e, :f}]

      map_state = Storage.Map.init(schemas)
      map_state = Storage.Map.insert_many(map_state, "rel", tuples)
      map_state = Storage.Map.insert(map_state, "val", {:x, 1})

      ets_state = Storage.ETS.init(schemas)
      ets_state = Storage.ETS.insert_many(ets_state, "rel", tuples)
      ets_state = Storage.ETS.insert(ets_state, "val", {:x, 1})

      {:ok, map_state: map_state, ets_state: ets_state, tuples: tuples}
    end

    test "member? gives identical results", %{map_state: ms, ets_state: es} do
      assert Storage.Map.member?(ms, "rel", {:a, :b}) == Storage.ETS.member?(es, "rel", {:a, :b})
      assert Storage.Map.member?(ms, "rel", {:x, :y}) == Storage.ETS.member?(es, "rel", {:x, :y})
      assert Storage.Map.member?(ms, "val", {:x, 1}) == Storage.ETS.member?(es, "val", {:x, 1})
    end

    test "size gives identical results", %{map_state: ms, ets_state: es} do
      assert Storage.Map.size(ms, "rel") == Storage.ETS.size(es, "rel")
      assert Storage.Map.size(ms, "val") == Storage.ETS.size(es, "val")
      assert Storage.Map.size(ms, "nonexistent") == Storage.ETS.size(es, "nonexistent")
    end

    test "stream gives identical sorted results", %{map_state: ms, ets_state: es} do
      assert Storage.Map.stream(ms, "rel") == Storage.ETS.stream(es, "rel")
      assert Storage.Map.stream(ms, "val") == Storage.ETS.stream(es, "val")
    end

    test "relations gives identical results", %{map_state: ms, ets_state: es} do
      assert Storage.Map.relations(ms) == Storage.ETS.relations(es)
    end

    test "capabilities differ by storage_type", %{map_state: ms, ets_state: es} do
      map_caps = Storage.Map.capabilities(ms)
      ets_caps = Storage.ETS.capabilities(es)
      assert map_caps.storage_type == :map
      assert ets_caps.storage_type == :ets
      assert ets_caps.indexed_lookup == true
      assert map_caps.indexed_lookup == false
    end
  end
end
