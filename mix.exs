defmodule Glific.MixProject do
  use Mix.Project

  def project do
    [
      app: :glific,
      version: "0.1.0",
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        "test.drop": :test
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Glific.Application, []},
      extra_applications: [:logger, :runtime_tools]
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
      {:phoenix, "~> 1.5.1"},
      {:phoenix_ecto, "~> 4.1"},
      {:ecto_sql, "~> 3.4"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_live_view, "~> 0.12.0"},
      {:floki, ">= 0.0.0", only: :test},
      {:phoenix_html, "~> 2.11"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_dashboard, "~> 0.2.0"},
      {:phoenix_pubsub, "~> 2.0"},
      {:telemetry_metrics, "~> 0.4"},
      {:telemetry_poller, "~> 0.4"},
      {:gettext, "~> 0.18"},
      {:decimal, "~> 1.8"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"},
      {:ecto_enum, "~> 1.4"},
      {:pow, "~> 1.0.20"},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:credo, "~> 1.4", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.22", only: [:dev], runtime: false},
      {:inch_ex, "~> 2.0", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.13.0"},
      {:httpoison, "~> 1.6"},
      {:poison, "~> 4.0"},
      {:ex_rated, "~> 1.2"},
      {:absinthe, "~> 1.5"},
      {:absinthe_plug, "~> 1.5"},
      {:absinthe_phoenix, "~> 2.0"},
      {:absinthe_relay, "~> 1.5"},
      {:dataloader, "~> 1.0.7"},
      {:hackney, "~> 1.16"},
      {:tesla, "~> 1.3.0"},
      {:oban, "~> 1.2"},
      {:faker, "~> 0.13", only: [:dev, :test]},
      {:excoveralls, "~> 0.13", only: :test},
      {:cors_plug, "~> 2.0"},
      {:ex_check, ">= 0.0.0", only: :dev, runtime: false},
      {:sobelow, "~> 0.8", only: :dev},
      {:wormwood, "~> 0.1.0"}
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
      setup: ["deps.get", "ecto.setup", "cmd npm install --prefix assets"],
      reset: ["deps.get", "compile", "ecto.reset", "cmd npm install --prefix assets"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.drop", "ecto.create --quiet", "ecto.migrate", "test"],
      "test.nodrop": ["ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end
end
