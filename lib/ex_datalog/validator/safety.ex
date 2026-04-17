defmodule ExDatalog.Validator.Safety do
  @moduledoc """
  Variable safety and range restriction checks for ExDatalog programs.

  A Datalog rule is **safe** when every variable in the rule head and in
  constraint inputs is bound by a positive body atom. Unsafe rules produce
  infinite or undefined results and must be rejected.

  ## Checks performed

  1. **Unsafe head variable** — a variable appears in the rule head but not
     in any positive body atom or arithmetic constraint result. Head variables
     must be range-restricted.

  2. **Unbound constraint variable** — a variable in a comparison constraint
     or in the input operands of an arithmetic constraint is not bound by any
     positive body atom or **earlier** arithmetic result. Constraints are
     validated in listed order; a result variable introduced by constraint `k`
     is only available to constraints `k+1` and later.

  3. **Wildcard in rule head** — wildcards (`:wildcard`) may not appear in
     rule heads because they do not bind a value.

  Wildcards in body atoms are allowed — they match any value without binding.

  ## Examples

      # Safe: X and Y are bound by positive body atoms
      ancestor(X, Y) :- parent(X, Y)

      # Unsafe: Z is not bound in any positive body atom
      ancestor(X, Z) :- parent(X, Y)          # ERROR: Z is unsafe

      # Safe: arithmetic result variable Z is bound by the constraint
      total(X, Z) :- value(X, A), value(Y, A), Z = X + Y

      # Unsafe ordering: W references Z before Z is computed
      bad(X, W) :- value(X, A), W = Z + 1, Z = A + 2   # ERROR: Z unbound at constraint 0

  """

  alias ExDatalog.{Atom, Constraint, Rule}
  alias ExDatalog.Validator.Error

  @doc """
    Checks all rules in a program for variable safety violations.

  Returns a list of `ExDatalog.Validator.Error.t()` (empty if all rules are safe).

  Each error includes:
  - `kind` — `:unsafe_variable`, `:unbound_constraint_variable`, or `:wildcard_in_head`
  - `context` — `%{rule_index: i, variable: "X", ...}`
  - `message` — human-readable description
  """
  @spec check(ExDatalog.Program.t()) :: [Error.t()]
  def check(%ExDatalog.Program{rules: rules}) do
    rules
    |> Enum.with_index()
    |> Enum.flat_map(fn {rule, idx} -> check_rule(rule, idx) end)
  end

  @doc """
  Checks a single rule for variable safety violations.

  Returns a list of errors for that rule. Rules with invalid
  body literals (not `{:positive, _}` or `{:negative, _}`) are
  skipped — the structural validator catches those.
  """
  @spec check_rule(Rule.t(), non_neg_integer()) :: [Error.t()]
  def check_rule(%Rule{body: body} = rule, rule_index) do
    # Skip safety checks if any body literal is invalid — structural
    # validation will catch those.
    if Enum.all?(body, &valid_literal?/1) do
      # Variables bound by positive body atoms (the baseline for all checks).
      body_bound = positive_body_variables(rule)

      # For head safety: arithmetic results are also in scope regardless of
      # constraint order, because if the rule is evaluated at all, every
      # arithmetic constraint will have run.
      head_bound = all_bound_variables(rule)
      head_vars = Rule.head_variables(rule)

      []
      |> check_wildcards_in_head(rule, rule_index)
      |> check_unsafe_head_variables(head_vars, head_bound, rule_index)
      |> check_unbound_constraint_variables(rule, body_bound, rule_index)
    else
      []
    end
  end

  defp valid_literal?({:positive, %Atom{}}), do: true
  defp valid_literal?({:negative, %Atom{}}), do: true
  defp valid_literal?(_), do: false

  # --- Private helpers ---

  # Variables bound by positive body atoms only.
  # This is the starting bound set for sequential constraint validation.
  # Wildcards do not bind. Negative atoms do not bind (safety rule).
  defp positive_body_variables(%Rule{body: body}) do
    body
    |> Enum.flat_map(fn
      {:positive, atom} -> Atom.variables(atom)
      _ -> []
    end)
    |> Enum.uniq()
  end

  # Variables bound by positive body atoms plus ALL arithmetic constraint results.
  # Used for head-variable safety: if the rule body evaluates at all, every
  # arithmetic constraint will have computed its result, so arithmetic results
  # are in scope for the head regardless of constraint ordering.
  defp all_bound_variables(%Rule{constraints: constraints} = rule) do
    arithmetic_result_vars =
      Enum.flat_map(constraints, fn c ->
        if Constraint.arithmetic?(c), do: [Constraint.result_variable(c)], else: []
      end)

    (positive_body_variables(rule) ++ arithmetic_result_vars) |> Enum.uniq()
  end

  defp check_wildcards_in_head(errors, %Rule{head: head}, rule_index) do
    Enum.reduce(head.terms, errors, fn
      :wildcard, acc ->
        [
          Error.new(
            :wildcard_in_head,
            %{rule_index: rule_index, relation: head.relation},
            "rule #{rule_index}: wildcard in head of relation #{inspect(head.relation)}; " <>
              "head terms must be variables or constants"
          )
          | acc
        ]

      _, acc ->
        acc
    end)
  end

  defp check_unsafe_head_variables(errors, head_vars, bound, rule_index) do
    Enum.reduce(head_vars, errors, fn var, acc ->
      if var in bound do
        acc
      else
        [
          Error.new(
            :unsafe_variable,
            %{rule_index: rule_index, variable: var},
            "rule #{rule_index}: variable #{inspect(var)} in head is not bound " <>
              "by any positive body atom or arithmetic constraint"
          )
          | acc
        ]
      end
    end)
  end

  defp check_unbound_constraint_variables(
         errors,
         %Rule{constraints: constraints},
         body_bound,
         rule_index
       ) do
    # Process constraints in order, threading the bound set.
    # Each arithmetic constraint extends the bound set with its result variable
    # for subsequent constraints. Comparison constraints do not extend the bound set.
    {errors_out, _final_bound} =
      constraints
      |> Enum.with_index()
      |> Enum.reduce({errors, body_bound}, fn {c, c_idx}, {acc_errors, bound} ->
        {new_errors, new_bound} = check_constraint(c, c_idx, bound, rule_index, acc_errors)
        {new_errors, new_bound}
      end)

    errors_out
  end

  defp check_constraint(%Constraint{} = c, c_idx, bound, rule_index, acc) do
    input_vars = Constraint.input_variables(c)
    unbound = Enum.reject(input_vars, fn var -> var in bound end)

    new_errors =
      if unbound == [] do
        acc
      else
        [
          Error.new(
            :unbound_constraint_variable,
            %{rule_index: rule_index, constraint_index: c_idx, variables: unbound, op: c.op},
            "rule #{rule_index}, constraint #{c_idx}: #{Enum.join(unbound, ", ")} " <>
              "not bound before #{c.op} constraint"
          )
          | acc
        ]
      end

    # Arithmetic constraints extend the bound set with their result variable
    # so that subsequent constraints may reference it.
    new_bound =
      if Constraint.arithmetic?(c) do
        case Constraint.result_variable(c) do
          nil -> bound
          var -> Enum.uniq([var | bound])
        end
      else
        bound
      end

    {new_errors, new_bound}
  end
end
