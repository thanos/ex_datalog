alias ExDatalog
alias ExDatalog.{Program, Rule, Atom, Term}

n = 50

chain_facts = for i <- 0..(n - 2), do: {String.to_atom("n#{i}"), String.to_atom("n#{i + 1}")}

program =
  Program.new()
  |> Program.add_relation("parent", [:atom, :atom])
  |> Program.add_relation("ancestor", [:atom, :atom])

program =
  Enum.reduce(chain_facts, program, fn {p, c}, acc ->
    Program.add_fact(acc, "parent", [p, c])
  end)

program =
  program
  |> Program.add_rule(
    Rule.new(
      Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
      [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
    )
  )
  |> Program.add_rule(
    Rule.new(
      Atom.new("ancestor", [Term.var("X"), Term.var("Z")]),
      [
        {:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])},
        {:positive, Atom.new("ancestor", [Term.var("Y"), Term.var("Z")])}
      ]
    )
  )

goal = {"ancestor", [String.to_atom("n0"), :_]}

Benchee.run(
  %{
    "semi_naive_full" => fn ->
      {:ok, _knowledge} = ExDatalog.materialize(program)
    end,
    "magic_sets_goal_driven" => fn ->
      {:ok, _knowledge} = ExDatalog.materialize(program, strategy: :magic_sets, goal: goal)
    end
  },
  time: 10,
  memory_time: 2,
  formatters: [{Benchee.Formatters.Console, comparison: true}],
  print: [fast_warning: false]
)
