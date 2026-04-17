defmodule ExDatalog.ResultTest do
  use ExUnit.Case, async: true

  alias ExDatalog.Result

  describe "get/2" do
    test "returns MapSet of tuples for a relation" do
      result = %Result{
        relations: %{"parent" => MapSet.new([{:alice, :bob}])},
        stats: %{iterations: 1, duration_us: 0, relation_sizes: %{"parent" => 1}}
      }

      assert Result.get(result, "parent") == MapSet.new([{:alice, :bob}])
    end

    test "returns empty MapSet for unknown relation" do
      result = %Result{
        relations: %{},
        stats: %{iterations: 0, duration_us: 0, relation_sizes: %{}}
      }

      assert Result.get(result, "unknown") == MapSet.new()
    end
  end

  describe "match/3" do
    test "matches tuples by pattern" do
      result = %Result{
        relations: %{
          "parent" => MapSet.new([{:alice, :bob}, {:alice, :carol}, {:bob, :dave}])
        },
        stats: %{iterations: 1, duration_us: 0, relation_sizes: %{}}
      }

      matched = Result.match(result, "parent", [:alice, :_])
      assert MapSet.size(matched) == 2
      assert {:alice, :bob} in matched
      assert {:alice, :carol} in matched
    end

    test "matches with all wildcards" do
      result = %Result{
        relations: %{"parent" => MapSet.new([{:alice, :bob}])},
        stats: %{iterations: 1, duration_us: 0, relation_sizes: %{}}
      }

      matched = Result.match(result, "parent", [:_, :_])
      assert MapSet.size(matched) == 1
    end

    test "matches with exact values" do
      result = %Result{
        relations: %{
          "parent" => MapSet.new([{:alice, :bob}, {:carol, :dave}])
        },
        stats: %{iterations: 1, duration_us: 0, relation_sizes: %{}}
      }

      matched = Result.match(result, "parent", [:alice, :bob])
      assert MapSet.size(matched) == 1
      assert {:alice, :bob} in matched
    end
  end

  describe "size/2" do
    test "returns number of tuples" do
      result = %Result{
        relations: %{"parent" => MapSet.new([{:a, :b}, {:c, :d}])},
        stats: %{iterations: 1, duration_us: 0, relation_sizes: %{}}
      }

      assert Result.size(result, "parent") == 2
    end
  end

  describe "relations/1" do
    test "returns sorted list of relation names" do
      result = %Result{
        relations: %{"z" => MapSet.new(), "a" => MapSet.new()},
        stats: %{iterations: 0, duration_us: 0, relation_sizes: %{}}
      }

      assert Result.relations(result) == ["a", "z"]
    end
  end
end
