defmodule Glific.MixProject do
  use Mix.Project

  @github_url "https://github.com/glific/glific/"
  @home_url "https://glific.io"

  def project do
    [
      app: :glific,
      version: "0.2.0",
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
      releases: [
        prod: [
          include_executable_for: [:unix],
          steps: [:assemble, :tar]
        ]
      ],
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      docs: [
        main: "readme",
        extras: ["README.md", "CHANGELOG.md"]
      ],
      preferred_cli_env: [
        coveralls: :test
      ],

      # Lets add meta information on project
      name: "Glific",
      description: "An open source two way communication platform for the social sector",
      source_url: @github_url,
      homepage_url: @home_url,
      package: [
        maintainers: ["Glific Project Team"],
        licenses: ["AGPL 3.0"],
        links: %{
          "GitHub" => @github_url
        }
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Glific.Application, []},
      extra_applications: [:logger, :runtime_tools, :mnesia]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.5"},
      {:phoenix_ecto, "~> 4.1"},
      {:ecto_sql, "~> 3.4"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_live_view, "~> 0.13"},
      {:floki, ">= 0.0.0", only: :test},
      {:phoenix_html, "~> 2.11"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_dashboard, "~> 0.2"},
      {:phoenix_pubsub, "~> 2.0"},
      {:telemetry_metrics, "~> 0.4"},
      {:telemetry_poller, "~> 0.4"},
      {:gettext, "~> 0.18"},
      {:decimal, "~> 1.8"},
      {:jason, "~> 1.2"},
      {:sentry, "~> 7.2"},
      {:plug_cowboy, "~> 2.0"},
      {:ecto_enum, "~> 1.4"},
      {:pow, "~> 1.0"},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.22", only: [:dev, :test], runtime: false},
      {:inch_ex, "~> 2.0", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.13"},
      {:httpoison, "~> 1.6"},
      {:poison, "~> 4.0"},
      {:ex_rated, "~> 1.2"},
      {:absinthe, "~> 1.5"},
      {:absinthe_plug, "~> 1.5"},
      {:absinthe_phoenix, "~> 2.0"},
      {:absinthe_relay, "~> 1.5"},
      {:dataloader, "~> 1.0"},
      {:hackney, "~> 1.16"},
      {:tesla, "~> 1.3"},
      {:oban, "~> 1.2"},
      {:faker, "~> 0.13"},
      {:excoveralls, "~> 0.13", only: :test},
      {:cors_plug, "~> 2.0"},
      {:ex_check, ">= 0.12.0", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.8", only: [:dev, :test]},
      {:wormwood, "~> 0.1"},
      {:gen_stage, "~> 1.0"},
      {:timex, "~> 3.0"},
      {:slugify, "~> 1.3"},
      {:cachex, "~> 3.2"},
      {:passwordless_auth, git: "https://github.com/glific/passwordless_auth.git"},
      {:phil_columns, git: "https://github.com/glific/phil_columns-ex.git"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "compile", "ecto.reset", "cmd npm install --prefix assets"],
      reset: ["deps.get", "clean", "compile", "ecto.reset", "cmd npm install --prefix assets"],
      "ecto.setup": [
        "ecto.create --quiet",
        "ecto.migrate",
        "phil_columns.seed",
        "run priv/repo/seeds_dev.exs"
      ],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      # test: ["ecto.create --quiet", "ecto.migrate", "test"]
      test: [
        "ecto.drop",
        "ecto.create --quiet",
        "ecto.migrate",
        "phil_columns.seed",
        "test"
      ]
    ]
  end
end
