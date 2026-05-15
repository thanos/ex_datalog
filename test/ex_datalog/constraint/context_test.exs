defmodule ExDatalog.Constraint.ContextTest do
  use ExUnit.Case, async: true

  alias ExDatalog.Capabilities
  alias ExDatalog.Constraint.Context

  describe "new/0" do
    test "creates context with default capabilities" do
      ctx = Context.new()
      assert %Context{} = ctx
      assert %Capabilities{} = ctx.capabilities
      assert ctx.provenance == false
    end
  end

  describe "new/1" do
    test "creates context with given capabilities" do
      caps = %Capabilities{storage_type: :ets, indexed_lookup: true}
      ctx = Context.new(caps)
      assert ctx.capabilities.storage_type == :ets
      assert ctx.capabilities.indexed_lookup == true
    end
  end

  describe "new/2" do
    test "creates context with capabilities and provenance" do
      caps = %Capabilities{}
      ctx = Context.new(caps, true)
      assert ctx.capabilities == caps
      assert ctx.provenance == true
    end
  end
end
