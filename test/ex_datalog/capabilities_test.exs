defmodule ExDatalog.CapabilitiesTest do
  use ExUnit.Case, async: true

  alias ExDatalog.Capabilities

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
end
