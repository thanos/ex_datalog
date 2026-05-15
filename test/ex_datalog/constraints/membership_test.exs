defmodule ExDatalog.Constraints.MembershipTest do
  use ExUnit.Case, async: true

  alias ExDatalog.Constraint.Context
  alias ExDatalog.Constraints.Membership
  alias ExDatalog.IR.Constraint

  describe "evaluate/3 — member" do
    test "passes when value is in the list" do
      c = %Constraint{
        op: :member,
        left: {:var, "X"},
        right: {:const, {:list, [{:atom, :a}, {:atom, :b}, {:atom, :c}]}},
        result: nil
      }

      assert {:ok, %{"X" => :a}} = Membership.evaluate(c, %{"X" => :a}, %Context{})
    end

    test "filters when value is not in the list" do
      c = %Constraint{
        op: :member,
        left: {:var, "X"},
        right: {:const, {:list, [{:atom, :a}, {:atom, :b}, {:atom, :c}]}},
        result: nil
      }

      assert :filter = Membership.evaluate(c, %{"X" => :d}, %Context{})
    end

    test "passes with integer value in integer list" do
      c = %Constraint{
        op: :member,
        left: {:var, "X"},
        right: {:const, {:list, [{:int, 1}, {:int, 2}, {:int, 3}]}},
        result: nil
      }

      assert {:ok, %{"X" => 2}} = Membership.evaluate(c, %{"X" => 2}, %Context{})
    end

    test "passes with string value in string list" do
      c = %Constraint{
        op: :member,
        left: {:var, "X"},
        right: {:const, {:list, [{:str, "foo"}, {:str, "bar"}]}},
        result: nil
      }

      assert {:ok, %{"X" => "foo"}} = Membership.evaluate(c, %{"X" => "foo"}, %Context{})
    end

    test "filters when left variable is unbound" do
      c = %Constraint{
        op: :member,
        left: {:var, "X"},
        right: {:const, {:list, [{:atom, :a}, {:atom, :b}]}},
        result: nil
      }

      assert :filter = Membership.evaluate(c, %{}, %Context{})
    end

    test "filters when left is a constant not in list" do
      c = %Constraint{
        op: :member,
        left: {:const, {:atom, :d}},
        right: {:const, {:list, [{:atom, :a}, {:atom, :b}, {:atom, :c}]}},
        result: nil
      }

      assert :filter = Membership.evaluate(c, %{}, %Context{})
    end

    test "passes when left constant is in list" do
      c = %Constraint{
        op: :member,
        left: {:const, {:atom, :a}},
        right: {:const, {:list, [{:atom, :a}, {:atom, :b}, {:atom, :c}]}},
        result: nil
      }

      assert {:ok, %{}} = Membership.evaluate(c, %{}, %Context{})
    end

    test "filters when right is not a constant list" do
      c = %Constraint{
        op: :member,
        left: {:var, "X"},
        right: {:const, {:int, 5}},
        result: nil
      }

      assert :filter = Membership.evaluate(c, %{"X" => 5}, %Context{})
    end
  end

  describe "evaluate/3 — wildcard" do
    test "filters when left operand is wildcard" do
      c = %Constraint{
        op: :member,
        left: :wildcard,
        right: {:const, {:list, [{:atom, :a}, {:atom, :b}]}},
        result: nil
      }

      assert :filter = Membership.evaluate(c, %{}, %Context{})
    end
  end
end
