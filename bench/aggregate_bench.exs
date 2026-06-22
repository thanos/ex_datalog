alias ExDatalog
alias ExDatalog.{Program, Rule, Atom, Term, Constraint}

{n, m} = {200, 5}

departments = for i <- 0..(m - 1), do: String.to_atom("dept_#{i}")

base_program =
  Program.new()
  |> Program.add_relation("emp", [:atom, :atom])
  |> Program.add_relation("salary", [:atom, :atom, :integer])

base_program =
  Enum.reduce(1..n, base_program, fn i, acc ->
    dept = Enum.at(departments, rem(i, m))
    salary = 50_000 + i * 100
    name = String.to_atom("emp_#{i}")

    acc
    |> Program.add_fact("emp", [name, dept])
    |> Program.add_fact("salary", [name, dept, salary])
  end)

program_no_aggregates =
  base_program
  |> Program.add_relation("emp_salary", [:atom, :atom, :integer])
  |> Program.add_rule(
    Rule.new(
      Atom.new("emp_salary", [Term.var("E"), Term.var("D"), Term.var("S")]),
      [{:positive, Atom.new("salary", [Term.var("E"), Term.var("D"), Term.var("S")])}]
    )
  )

program_with_aggregates =
  base_program
  |> Program.add_relation("dept_count", [:atom, :integer])
  |> Program.add_relation("dept_total", [:atom, :integer])
  |> Program.add_relation("dept_min_salary", [:atom, :integer])
  |> Program.add_relation("dept_max_salary", [:atom, :integer])
  |> Program.add_rule(
    Rule.new(
      Atom.new("dept_count", [Term.var("D"), Term.var("N")]),
      [{:positive, Atom.new("emp", [Term.var("E"), Term.var("D")])}],
      [Constraint.count(Term.var("E"), Term.var("N"))]
    )
  )
  |> Program.add_rule(
    Rule.new(
      Atom.new("dept_total", [Term.var("D"), Term.var("T")]),
      [{:positive, Atom.new("salary", [Term.var("E"), Term.var("D"), Term.var("A")])}],
      [Constraint.sum(Term.var("A"), Term.var("T"))]
    )
  )
  |> Program.add_rule(
    Rule.new(
      Atom.new("dept_min_salary", [Term.var("D"), Term.var("V")]),
      [{:positive, Atom.new("salary", [Term.var("E"), Term.var("D"), Term.var("S")])}],
      [Constraint.min(Term.var("S"), Term.var("V"))]
    )
  )
  |> Program.add_rule(
    Rule.new(
      Atom.new("dept_max_salary", [Term.var("D"), Term.var("V")]),
      [{:positive, Atom.new("salary", [Term.var("E"), Term.var("D"), Term.var("S")])}],
      [Constraint.max(Term.var("S"), Term.var("V"))]
    )
  )

Benchee.run(
  %{
    "no_aggregates" => fn ->
      {:ok, _knowledge} = ExDatalog.materialize(program_no_aggregates)
    end,
    "with_aggregates_count_sum_min_max" => fn ->
      {:ok, _knowledge} = ExDatalog.materialize(program_with_aggregates)
    end
  },
  time: 10,
  memory_time: 2,
  formatters: [{Benchee.Formatters.Console, comparison: true}],
  print: [fast_warning: false]
)
