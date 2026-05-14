defmodule ExDatalog.Storage.ETSTest do
  use ExUnit.Case, async: true

  alias ExDatalog.Storage.ETS

  @schemas %{
    "parent" => %{arity: 2, types: [:atom, :atom]},
    "ancestor" => %{arity: 2, types: [:atom, :atom]},
    "value" => %{arity: 2, types: [:atom, :integer]}
  }

  describe "init/2 options" do
    test "creates private tables by default" do
      state = ETS.init(@schemas)
      assert %ETS{} = state
      assert state.options[:access] == :private
      ETS.teardown(state)
    end

    test "creates public tables when access: :public" do
      state = ETS.init(@schemas, access: :public)
      assert state.options[:access] == :public
      ETS.teardown(state)
    end
  end

  describe "capabilities/1" do
    test "reports :ets storage type with private access" do
      state = ETS.init(@schemas)
      caps = ETS.capabilities(state)
      assert caps.storage_type == :ets
      assert caps.indexed_lookup == true
      assert caps.concurrent_reads == false
      ETS.teardown(state)
    end

    test "reports :public concurrent_reads with access: :public" do
      state = ETS.init(@schemas, access: :public)
      caps = ETS.capabilities(state)
      assert caps.concurrent_reads == true
      ETS.teardown(state)
    end
  end

  describe "teardown/1" do
    test "deletes all ETS tables" do
      state = ETS.init(@schemas)
      tables = state.tables
      assert map_size(tables) > 0

      for {_name, ref} <- tables do
        assert :ets.info(ref, :name) != :undefined
      end

      assert :ok == ETS.teardown(state)

      for {_name, ref} <- tables do
        assert :ets.info(ref, :name) == :undefined
      end
    end

    test "is idempotent (double teardown does not crash)" do
      state = ETS.init(@schemas)
      assert :ok == ETS.teardown(state)
      assert :ok == ETS.teardown(state)
    end
  end

  describe "large workload" do
    test "handles >10K facts" do
      state = ETS.init(@schemas)

      tuples =
        for i <- 1..10_000 do
          {String.to_atom("node_#{i}"), String.to_atom("val_#{i}")}
        end

      state = ETS.insert_many(state, "parent", tuples)
      assert ETS.size(state, "parent") == 10_000

      # Pick a tuple from the middle to verify membership
      mid_tuple = Enum.at(tuples, 5000)
      assert ETS.member?(state, "parent", mid_tuple)

      stream = ETS.stream(state, "parent")
      assert length(stream) == 10_000

      ETS.teardown(state)
    end

    test "stream returns deterministically sorted output for large sets" do
      state = ETS.init(@schemas)

      tuples =
        for i <- 1..5_000 do
          {i, i * 2}
        end

      state = ETS.insert_many(state, "value", tuples)
      stream = ETS.stream(state, "value")
      assert stream == Enum.sort(tuples)

      ETS.teardown(state)
    end

    test "correctly stores multiple tuples sharing the same first element" do
      state = ETS.init(@schemas)

      state = ETS.insert(state, "parent", {:alice, :bob})
      state = ETS.insert(state, "parent", {:alice, :carol})
      state = ETS.insert(state, "parent", {:alice, :dave})

      assert ETS.size(state, "parent") == 3
      assert ETS.member?(state, "parent", {:alice, :bob})
      assert ETS.member?(state, "parent", {:alice, :carol})
      assert ETS.member?(state, "parent", {:alice, :dave})

      stream = ETS.stream(state, "parent")
      assert stream == [{:alice, :bob}, {:alice, :carol}, {:alice, :dave}]

      ETS.teardown(state)
    end
  end

  describe "wrapped tuple key semantics" do
    test "insert then member? with shared first element" do
      state = ETS.init(@schemas)
      state = ETS.insert(state, "parent", {:alice, :bob})
      assert ETS.member?(state, "parent", {:alice, :bob})
      refute ETS.member?(state, "parent", {:alice, :carol})
      ETS.teardown(state)
    end

    test "distinct tuples with same first element are preserved" do
      state = ETS.init(@schemas)
      state = ETS.insert(state, "parent", {:a, 1})
      state = ETS.insert(state, "parent", {:a, 2})
      state = ETS.insert(state, "parent", {:a, 3})
      assert ETS.size(state, "parent") == 3
      assert ETS.stream(state, "parent") == [{:a, 1}, {:a, 2}, {:a, 3}]
      ETS.teardown(state)
    end
  end

  describe "insert mutates ETS tables in place" do
    test "insert/3 makes tuple immediately visible via member?" do
      state = ETS.init(@schemas)
      state = ETS.insert(state, "parent", {:alice, :bob})
      assert ETS.member?(state, "parent", {:alice, :bob})
      refute ETS.member?(state, "parent", {:alice, :carol})
      ETS.teardown(state)
    end

    test "insert_many/3 makes all tuples immediately visible" do
      state = ETS.init(@schemas)
      state = ETS.insert_many(state, "parent", [{:a, :b}, {:c, :d}])
      assert ETS.size(state, "parent") == 2
      assert ETS.member?(state, "parent", {:a, :b})
      assert ETS.member?(state, "parent", {:c, :d})
      ETS.teardown(state)
    end
  end
end
