defmodule ExDatalog.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/anomalyco/ex_datalog"

  def project do
    [
      app: :ex_datalog,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),

      # Hex metadata
      description:
        "A production-grade pure Elixir Datalog engine with semi-naive fixpoint evaluation.",
      package: package(),

      # ExDoc
      name: "ExDatalog",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),

      # Test coverage
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Dev + test tooling
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      lint: [
        "format --check-formatted",
        "credo --strict",
        "dialyzer --format github"
      ],
      "lint.fix": ["format", "credo --strict"],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --check-unused",
        "format"
      ],
      verify: &verify/1
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:ex_unit],
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      flags: [:error_handling, :underspecs]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "ExDatalog",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md"],
      groups_for_modules: [
        "Program Builder": [
          ExDatalog.Program,
          ExDatalog.Rule,
          ExDatalog.Atom,
          ExDatalog.Term,
          ExDatalog.Constraint
        ],
        Validation: [
          ExDatalog.Validator,
          ExDatalog.Validator.Error,
          ExDatalog.Validator.Safety,
          ExDatalog.Validator.Stratification
        ],
        "Compiler & IR": ~r/ExDatalog\.(Compiler|IR).*/,
        Engine: ~r/ExDatalog\.Engine.*/,
        Storage: ~r/ExDatalog\.Storage.*/,
        Results: [
          ExDatalog.Result,
          ExDatalog.Explain,
          ExDatalog.Telemetry
        ]
      ]
    ]
  end

  defp verify(_) do
    steps = [
      {"compile --warnings-as-errors", :dev},
      {"format --check-formatted", :dev},
      {"credo --strict", :dev},
      # {"sobelow --config", :dev},
      {"dialyzer", :dev},
      {"test --cover", :test},
      {"docs --warnings-as-errors", :dev}
    ]

    Enum.each(steps, fn {task, env} ->
      Mix.shell().info(IO.ANSI.format([:bright, "==> mix #{task}", :reset]))

      mix_executable =
        System.find_executable("mix") ||
          Mix.raise("Could not find `mix` executable on PATH")

      {_, exit_code} =
        System.cmd(mix_executable, String.split(task),
          env: [{"MIX_ENV", to_string(env)}],
          into: IO.stream(:stdio, :line),
          stderr_to_stdout: true
        )

      if exit_code != 0 do
        Mix.raise("mix #{task} failed (exit code #{exit_code})")
      end
    end)

    Mix.shell().info(
      IO.ANSI.format([:green, :bright, "\nAll verification checks passed!", :reset])
    )
  end
end
