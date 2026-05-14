defmodule ExDatalog.CapabilitiesTest do
  use ExUnit.Case, async: true
  doctest ExDatalog.Capabilities

  alias ExDatalog.Capabilities
  alias ExDatalog.Storage.ETS

  describe "default/0" do
    test "returns the default capabilities struct" do
      caps = Capabilities.default()
      assert %Capabilities{} = caps
      assert caps.storage_type == :map
      assert caps.indexed_lookup == false
      assert caps.concurrent_reads == false
      assert caps.arithmetic_constraints == true
      assert caps.comparison_constraints == true
      assert caps.type_predicates == true
      assert caps.string_predicates == true
      assert caps.provenance == true
      assert caps.external_execution == false
    end
  end

  describe "struct defaults" do
    test "all fields have correct defaults" do
      caps = %Capabilities{}
      assert caps.storage_type == :map
      assert caps.indexed_lookup == false
      assert caps.concurrent_reads == false
      assert caps.arithmetic_constraints == true
      assert caps.comparison_constraints == true
      assert caps.type_predicates == true
      assert caps.string_predicates == true
      assert caps.provenance == true
      assert caps.external_execution == false
    end
  end

  describe "merge/2" do
    test "AND semantics: true AND true = true" do
      left = %Capabilities{arithmetic_constraints: true, indexed_lookup: true}
      right = %Capabilities{arithmetic_constraints: true, indexed_lookup: true}
      merged = Capabilities.merge(left, right)
      assert merged.arithmetic_constraints == true
      assert merged.indexed_lookup == true
    end

    test "AND semantics: true AND false = false" do
      left = %Capabilities{arithmetic_constraints: true}
      right = %Capabilities{arithmetic_constraints: false}
      merged = Capabilities.merge(left, right)
      assert merged.arithmetic_constraints == false
    end

    test "AND semantics: false AND true = false" do
      left = %Capabilities{indexed_lookup: false}
      right = %Capabilities{indexed_lookup: true}
      merged = Capabilities.merge(left, right)
      assert merged.indexed_lookup == false
    end

    test "AND semantics: false AND false = false" do
      left = %Capabilities{concurrent_reads: false}
      right = %Capabilities{concurrent_reads: false}
      merged = Capabilities.merge(left, right)
      assert merged.concurrent_reads == false
    end

    test "storage_type takes left operand" do
      left = %Capabilities{storage_type: :ets}
      right = %Capabilities{storage_type: :map}
      merged = Capabilities.merge(left, right)
      assert merged.storage_type == :ets
    end

    test "merges all fields" do
      left = %Capabilities{storage_type: :ets, indexed_lookup: true, concurrent_reads: true}
      right = %Capabilities{storage_type: :map, indexed_lookup: true, concurrent_reads: false}
      merged = Capabilities.merge(left, right)
      assert merged.storage_type == :ets
      assert merged.indexed_lookup == true
      assert merged.concurrent_reads == false
    end
  end

  describe "satisfies?/2" do
    test "returns true when all requirements are met" do
      caps = %Capabilities{arithmetic_constraints: true, indexed_lookup: true}
      assert Capabilities.satisfies?(caps, arithmetic_constraints: true, indexed_lookup: true)
    end

    test "returns false when a requirement is not met" do
      caps = %Capabilities{arithmetic_constraints: true, concurrent_reads: false}
      refute Capabilities.satisfies?(caps, arithmetic_constraints: true, concurrent_reads: true)
    end

    test "returns true for empty requirements" do
      caps = %Capabilities{}
      assert Capabilities.satisfies?(caps, [])
    end

    test "returns false when requirement value is false and field is true" do
      caps = %Capabilities{indexed_lookup: true}
      refute Capabilities.satisfies?(caps, indexed_lookup: false)
    end

    test "single requirement" do
      caps = %Capabilities{arithmetic_constraints: true}
      assert Capabilities.satisfies?(caps, arithmetic_constraints: true)
    end
  end

  describe "from_backend/1" do
    test "queries Map backend capabilities" do
      schemas = %{"rel" => %{arity: 2, types: [:integer, :string]}}
      state = ExDatalog.Storage.Map.init(schemas)
      caps = Capabilities.from_backend({ExDatalog.Storage.Map, state})
      assert %Capabilities{} = caps
      assert caps.storage_type == :map
      assert caps.indexed_lookup == false
    end

    test "queries ETS backend capabilities" do
      schemas = %{"rel" => %{arity: 2, types: [:integer, :string]}}
      state = ETS.init(schemas)
      caps = Capabilities.from_backend({ETS, state})
      assert %Capabilities{} = caps
      assert caps.storage_type == :ets
      assert caps.indexed_lookup == true
      ETS.teardown(state)
    end
  end
end
