defmodule ExDatalog.Constraints.StringTest do
  use ExUnit.Case, async: true

  alias ExDatalog.Constraint.Context
  alias ExDatalog.Constraints.String, as: StringPred
  alias ExDatalog.IR.Constraint

  describe "evaluate/3 — starts_with" do
    test "passes when string starts with prefix" do
      c = %Constraint{
        op: :starts_with,
        left: {:var, "X"},
        right: {:const, {:str, "hel"}},
        result: nil
      }

      assert {:ok, %{"X" => "hello"}} =
               StringPred.evaluate(c, %{"X" => "hello"}, %Context{})
    end

    test "filters when string does not start with prefix" do
      c = %Constraint{
        op: :starts_with,
        left: {:var, "X"},
        right: {:const, {:str, "xyz"}},
        result: nil
      }

      assert :filter = StringPred.evaluate(c, %{"X" => "hello"}, %Context{})
    end

    test "filters when left is not a binary" do
      c = %Constraint{
        op: :starts_with,
        left: {:var, "X"},
        right: {:const, {:str, "h"}},
        result: nil
      }

      assert :filter = StringPred.evaluate(c, %{"X" => 42}, %Context{})
    end

    test "filters when right is not a binary" do
      c = %Constraint{
        op: :starts_with,
        left: {:var, "X"},
        right: {:const, {:int, 1}},
        result: nil
      }

      assert :filter = StringPred.evaluate(c, %{"X" => "hello"}, %Context{})
    end

    test "filters when left variable is unbound" do
      c = %Constraint{
        op: :starts_with,
        left: {:var, "X"},
        right: {:const, {:str, "h"}},
        result: nil
      }

      assert :filter = StringPred.evaluate(c, %{}, %Context{})
    end

    test "both variables bound" do
      c = %Constraint{op: :starts_with, left: {:var, "X"}, right: {:var, "Y"}, result: nil}

      assert {:ok, %{"X" => "hello", "Y" => "hel"}} =
               StringPred.evaluate(c, %{"X" => "hello", "Y" => "hel"}, %Context{})
    end
  end

  describe "evaluate/3 — contains" do
    test "passes when string contains substring" do
      c = %Constraint{
        op: :contains,
        left: {:var, "X"},
        right: {:const, {:str, "ell"}},
        result: nil
      }

      assert {:ok, %{"X" => "hello"}} = StringPred.evaluate(c, %{"X" => "hello"}, %Context{})
    end

    test "filters when string does not contain substring" do
      c = %Constraint{
        op: :contains,
        left: {:var, "X"},
        right: {:const, {:str, "xyz"}},
        result: nil
      }

      assert :filter = StringPred.evaluate(c, %{"X" => "hello"}, %Context{})
    end

    test "filters when left is not a binary" do
      c = %Constraint{op: :contains, left: {:var, "X"}, right: {:const, {:str, "h"}}, result: nil}
      assert :filter = StringPred.evaluate(c, %{"X" => 42}, %Context{})
    end

    test "filters when right is not a binary" do
      c = %Constraint{op: :contains, left: {:var, "X"}, right: {:const, {:int, 1}}, result: nil}
      assert :filter = StringPred.evaluate(c, %{"X" => "hello"}, %Context{})
    end

    test "filters when a variable is unbound" do
      c = %Constraint{op: :contains, left: {:var, "X"}, right: {:const, {:str, "h"}}, result: nil}
      assert :filter = StringPred.evaluate(c, %{}, %Context{})
    end
  end

  describe "evaluate/3 — wildcard" do
    test "filters when operand is wildcard" do
      c = %Constraint{
        op: :starts_with,
        left: :wildcard,
        right: {:const, {:str, "h"}},
        result: nil
      }

      assert :filter = StringPred.evaluate(c, %{}, %Context{})
    end
  end
end
