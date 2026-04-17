defmodule ExDatalog.Validator.Safety do
  @moduledoc """
  Variable safety and range restriction checks for ExDatalog programs.

  A Datalog rule is **safe** when every variable in the rule head and in
  constraint inputs is bound by a positive body atom. Unsafe rules produce
  infinite or undefined results and must be rejected.

  ## Checks performed

  1. **Unsafe head variable** — a variable appears in the rule head but not
     in any positive body atom. Head variables must be range-restricted.

  2. **Unbound constraint variable** — a variable in a comparison constraint
     or in the input operands of an arithmetic constraint is not bound by any
     positive body atom or earlier arithmetic result.

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

  """

  alias ExDatalog.{Atom, Constraint, Rule}
  alias ExDatalog.Validator.Errors

  @doc """
  Checks all rules in a program for variable safety violations.

  Returns a list of `ExDatalog.Validator.Errors.t()` (empty if all rules are safe).

  Each error includes:
  - `kind` — `:unsafe_variable`, `:unbound_constraint_variable`, or `:wildcard_in_head`
  - `context` — `%{rule_index: i, variable: "X", ...}`
  - `message` — human-readable description
  """
  @spec check(ExDatalog.Program.t()) :: [Errors.t()]
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
  @spec check_rule(Rule.t(), non_neg_integer()) :: [Errors.t()]
  def check_rule(%Rule{body: body} = rule, rule_index) do
    # Skip safety checks if any body literal is invalid — structural
    # validation will catch those.
    if Enum.all?(body, &valid_literal?/1) do
      bound = bound_variables(rule)
      head_vars = Rule.head_variables(rule)

      []
      |> check_wildcards_in_head(rule, rule_index)
      |> check_unsafe_head_variables(head_vars, bound, rule_index)
      |> check_unbound_constraint_variables(rule, bound, rule_index)
    else
      []
    end
  end

  defp valid_literal?({:positive, %Atom{}}), do: true
  defp valid_literal?({:negative, %Atom{}}), do: true
  defp valid_literal?(_), do: false

  # --- Private helpers ---

  # The set of variables bound by positive body atoms.
  # Wildcards do not bind. Negative atoms do not bind (safety rule).
  defp bound_variables(%Rule{body: body, constraints: constraints}) do
    positive_vars =
      Enum.flat_map(body, fn
        {:positive, atom} -> Atom.variables(atom)
        {:negative, _} -> []
        _ -> []
      end)

    arithmetic_result_vars =
      Enum.flat_map(constraints, fn c ->
        if Constraint.arithmetic?(c), do: [Constraint.result_variable(c)], else: []
      end)

    (positive_vars ++ arithmetic_result_vars) |> Enum.uniq()
  end

  defp check_wildcards_in_head(errors, %Rule{head: head}, rule_index) do
    Enum.reduce(head.terms, errors, fn
      :wildcard, acc ->
        [
          Errors.new(
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
          Errors.new(
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
         bound,
         rule_index
       ) do
    Enum.reduce(Enum.with_index(constraints), errors, fn {c, c_idx}, acc ->
      check_constraint(c, c_idx, bound, rule_index, acc)
    end)
  end

  defp check_constraint(%Constraint{} = c, c_idx, bound, rule_index, acc) do
    input_vars = Constraint.input_variables(c)

    unbound =
      input_vars
      |> Enum.reject(fn var -> var in bound end)

    # For arithmetic constraints, the result variable must also not
    # shadow or duplicate a bound variable — but since it's a new binding,
    # it extends the bound set. We only check input variables here.
    if unbound == [] do
      acc
    else
      kind =
        if Constraint.comparison?(c) do
          :unbound_constraint_variable
        else
          :unbound_constraint_variable
        end

      [
        Errors.new(
          kind,
          %{rule_index: rule_index, constraint_index: c_idx, variables: unbound, op: c.op},
          "rule #{rule_index}, constraint #{c_idx}: #{Enum.join(unbound, ", ")} " <>
            "not bound before #{c.op} constraint"
        )
        | acc
      ]
    end
  end
end
