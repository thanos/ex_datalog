defmodule ExDatalog.Engine.JoinTest do
  use ExUnit.Case, async: true

  alias ExDatalog.Engine.{Binding, Join}

  describe "match_tuple/3" do
    test "matches variables and extends binding" do
      terms = [{:var, "X"}, {:var, "Y"}]
      assert Join.match_tuple(terms, {:alice, :bob}, %{}) == {:ok, %{"X" => :alice, "Y" => :bob}}
    end

    test "matches with existing binding on shared variable" do
      terms = [{:var, "X"}, {:var, "Y"}]

      assert Join.match_tuple(terms, {:alice, :bob}, %{"X" => :alice}) ==
               {:ok, %{"X" => :alice, "Y" => :bob}}
    end

    test "returns :no_match when bound variable disagrees" do
      terms = [{:var, "X"}, {:var, "Y"}]
      assert Join.match_tuple(terms, {:alice, :bob}, %{"X" => :carol}) == :no_match
    end

    test "matches same variable in two positions" do
      terms = [{:var, "X"}, {:var, "X"}]
      assert Join.match_tuple(terms, {:alice, :alice}, %{}) == {:ok, %{"X" => :alice}}
    end

    test "returns :no_match when same variable disagrees across positions" do
      terms = [{:var, "X"}, {:var, "X"}]
      assert Join.match_tuple(terms, {:alice, :bob}, %{}) == :no_match
    end

    test "matches constant term" do
      terms = [{:var, "X"}, {:const, {:atom, :bob}}]
      assert Join.match_tuple(terms, {:alice, :bob}, %{}) == {:ok, %{"X" => :alice}}
    end

    test "returns :no_match when constant disagrees" do
      terms = [{:var, "X"}, {:const, {:atom, :carol}}]
      assert Join.match_tuple(terms, {:alice, :bob}, %{}) == :no_match
    end

    test "matches wildcard" do
      terms = [:wildcard, {:var, "Y"}]
      assert Join.match_tuple(terms, {:ignored, :bob}, %{}) == {:ok, %{"Y" => :bob}}
    end

    test "matches integer constant" do
      terms = [{:var, "X"}, {:const, {:int, 42}}]
      assert Join.match_tuple(terms, {:any, 42}, %{}) == {:ok, %{"X" => :any}}
    end

    test "matches string constant" do
      terms = [{:var, "X"}, {:const, {:str, "hello"}}]
      assert Join.match_tuple(terms, {:any, "hello"}, %{}) == {:ok, %{"X" => :any}}
    end
  end

  describe "join/3" do
    test "joins a single binding with tuples" do
      terms = [{:var, "X"}, {:var, "Y"}]
      tuples = [{:alice, :bob}, {:carol, :dave}]
      result = Join.join([%{}], terms, tuples)
      assert length(result) == 2
      assert %{"X" => :alice, "Y" => :bob} in result
      assert %{"X" => :carol, "Y" => :dave} in result
    end

    test "joins with a pre-bound variable" do
      terms = [{:var, "X"}, {:var, "Y"}]
      tuples = [{:alice, :bob}, {:carol, :dave}]
      result = Join.join([%{"X" => :alice}], terms, tuples)
      assert result == [%{"X" => :alice, "Y" => :bob}]
    end

    test "joins multiple bindings with tuples" do
      terms = [{:var, "X"}, {:var, "Y"}]
      tuples = [{:alice, :bob}, {:carol, :dave}]
      result = Join.join([%{"X" => :alice}, %{"X" => :carol}], terms, tuples)
      assert length(result) == 2
    end

    test "returns empty when no tuples match" do
      terms = [{:var, "X"}, {:const, {:atom, :bob}}]
      tuples = [{:alice, :dave}]
      result = Join.join([%{}], terms, tuples)
      assert result == []
    end

    test "self-join: same variable in both positions" do
      terms = [{:var, "X"}, {:var, "X"}]
      tuples = [{:alice, :alice}, {:bob, :bob}, {:alice, :bob}]
      result = Join.join([%{}], terms, tuples)
      assert length(result) == 2
      assert %{"X" => :alice} in result
      assert %{"X" => :bob} in result
    end
  end

  describe "project/2" do
    test "projects binding onto head variables" do
      head = %ExDatalog.IR.Atom{relation: "ancestor", terms: [{:var, "X"}, {:var, "Y"}]}
      binding = %{"X" => :alice, "Y" => :bob, "Z" => :carol}
      assert Join.project(head, binding) == {:alice, :bob}
    end

    test "projects with constant in head" do
      head = %ExDatalog.IR.Atom{relation: "result", terms: [{:var, "X"}, {:const, {:atom, :ok}}]}
      binding = %{"X" => 42}
      assert Join.project(head, binding) == {42, :ok}
    end
  end

  describe "join_indexed/4" do
    test "joins using a pre-built hash index" do
      terms = [{:var, "X"}, {:var, "Y"}]
      index = %{{:alice} => [{:alice, :bob}, {:alice, :carol}]}
      bindings = [%{"X" => :alice}]
      result = Join.join_indexed(bindings, terms, index, [0])
      assert length(result) == 2
      assert %{"X" => :alice, "Y" => :bob} in result
      assert %{"X" => :alice, "Y" => :carol} in result
    end

    test "returns empty when key not in index" do
      terms = [{:var, "X"}, {:var, "Y"}]
      index = %{{:dave} => [{:dave, :eve}]}
      bindings = [%{"X" => :alice}]
      result = Join.join_indexed(bindings, terms, index, [0])
      assert result == []
    end
  end
end
