defmodule Glific.MixProject do
  use Mix.Project

  @github_url "https://github.com/glific/glific/"
  @home_url "https://glific.io"
  @test_envs [:test, :test_full]
  @oban_envs [:prod, :dev] ++ @test_envs
  # comment above line
  # if you don't have Oban pro license, this is your best hack
  # uncomment below line
  # @oban_envs [:prod]

  def project do
    [
      app: :glific,
      version: "8.2.0",
      elixir: "~> 1.18.3",
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        ignore_warnings: ".dialyzer_ignore.exs"
        # list_unused_filters: true
      ],
      releases: [
        prod: [
          include_executable_for: [:unix],
          steps: [:assemble, :tar]
        ]
      ],
      # to avoid compiler iex warning in application.ex
      xref: [exclude: [IEx]],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [
        tool: ExCoveralls,
        test_task: :test_full
      ],
      docs: [
        main: "readme",
        extras: ["README.md", "CHANGELOG.md"]
      ],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        test_full: :test,
        "test.watch": :test
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
        },
        exclude_patterns: ["priv/plts", "build_scripts/*", "assets/*"]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Glific.Application, []},
      extra_applications: [:logger, :runtime_tools, :mnesia, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(env) when env in @test_envs, do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_ecto, "~> 4.1"},
      {:phoenix_html, "~> 3.3"},
      {:phoenix_live_reload, "~> 1.4", only: [:dev | @test_envs]},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.7"},
      {:phoenix_view, "~> 2.0"},
      {:pbkdf2_elixir, "~> 2.0"},
      {:telemetry, "~> 1.0"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:ecto_sql, "~> 3.9"},
      {:ecto_psql_extras, "~> 0.8"},
      {:esbuild, "~> 0.6", runtime: Mix.env() == :dev},
      {:postgrex, "~> 0.20"},
      {:floki, ">= 0.27.0", only: @test_envs},
      {:gettext, "~> 0.22"},
      {:decimal, "~> 2.0"},
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.0"},
      {:ecto_enum, "~> 1.4"},
      {:dialyxir, "~> 1.2", only: [:dev | @test_envs], runtime: false},
      {:credo, "~> 1.6", only: [:dev | @test_envs], runtime: false},
      {:ex_doc, "~> 0.29", only: [:dev | @test_envs], runtime: false},
      {:inch_ex, "~> 2.0", only: [:dev | @test_envs], runtime: false},
      {:doctor, "~> 0.20"},
      {:poison, "~> 4.0"},
      {:ex_rated, "~> 2.0"},
      {:absinthe, "~> 1.7"},
      {:absinthe_plug, "~> 1.5"},
      {:absinthe_phoenix, "~> 2.0"},
      {:dataloader, "~> 2.0"},
      {:hackney, "~> 1.17"},
      {:tesla, "~> 1.5"},
      {:oban, "~> 2.19"},
      {:oban_web, "~> 2.11", only: @oban_envs},
      {:oban_pro, "~> 1.5", repo: "oban", only: @oban_envs},
      {:faker, "~> 0.13"},
      {:mock, "~> 0.3", only: [:dev | @test_envs]},
      {:excoveralls, "~> 0.15", only: @test_envs},
      {:publicist, "~> 1.1"},
      {:cors_plug, "~> 3.0"},
      {:ex_check, "~> 0.15", only: [:dev | @test_envs], runtime: false},
      {:sobelow, "~> 0.8", only: [:dev | @test_envs]},
      {:goth, "~> 1.3"},
      {:wormwood, "~> 0.1"},
      {:timex, "~> 3.7"},
      {:slugify, "~> 1.3"},
      {:cachex, "~> 3.6"},
      {:fun_with_flags, "~> 1.9"},
      {:fun_with_flags_ui, "~> 1.0"},
      {:passwordless_auth, "~> 0.3.0"},
      {:appsignal_phoenix, "~> 2.3"},
      {:poolboy, "~> 1.5"},
      {:cloak_ecto, "~> 1.2"},
      {:google_api_big_query, "~> 0.47"},
      {:google_api_dialogflow, "~> 0.62"},
      {:gpt3_tokenizer, "~> 0.1.0"},
      {:absinthe_graphql_ws, "~> 0.3"},
      {:google_api_sheets, "~> 0.29"},
      {:waffle, "~> 1.1"},
      {:waffle_ecto, "~> 0.0"},
      {:csv, "~> 3.2"},
      {:observer_cli, "~> 1.7"},
      {:apiac_filter_ip_whitelist, "~> 1.0"},
      {:ex_phone_number, "~> 0.3"},
      {:tzdata, "~> 1.1"},
      {:stripity_stripe, "~> 2.3"},
      {:stripe_mock, "~> 0.1", only: @test_envs},
      {:remote_ip, "~> 1.0"},
      {:exvcr, "~> 0.13", only: @test_envs},
      {:dotenvy, "~> 0.1"},
      {:tailwind, "~> 0.1", runtime: Mix.env() == :dev},
      {:phoenix_swoosh, "~> 1.2"},
      {:gen_smtp, "~> 1.1"},
      {:glific_phil_columns, "~> 3.2"},
      {:glific_forked_waffle_gcs, "~> 0.1.1"},
      {:pow, git: "https://github.com/glific/pow.git"},
      {:contex, "~> 0.5.0"},
      {:password_validator, "~> 0.5"},
      {:resvg, "~> 0.3.0"},
      {:google_api_translate, "~> 0.15"},
      {:passgen, "~> 0.1.1"},
      {:tarams, "~> 1.8"},
      {:mix_test_watch, "~> 1.2", only: @test_envs},
      {:ex_audit, "~> 0.10"}
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
      setup: ["deps.get", "common"],
      common: ["clean", "compile", "ecto.reset", "assets.deploy"],
      "ecto.setup": [
        "ecto.create --quiet",
        "ecto.load --quiet --skip-if-loaded",
        "ecto.migrate --quiet",
        "phil_columns.seed --tenant glific",
        "run priv/repo/seeds_dev.exs",
        "run priv/repo/seeds_credentials.exs"
      ],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "ecto.scale": [
        "ecto.reset",
        "run priv/repo/seeds_scale.exs"
      ],
      "ecto.scale_2": [
        "phil_columns.seed --tenant org_2",
        "run priv/repo/seeds_scale.exs --organization 2 --contacts 250"
      ],
      test_full: [
        "ecto.drop",
        "ecto.create --quiet",
        "ecto.load --quiet --skip-if-loaded",
        "ecto.migrate --quiet",
        "phil_columns.seed --tenant glific",
        "test"
      ],
      test: [
        "ecto.create --quiet",
        "ecto.load --quiet --skip-if-loaded",
        "ecto.migrate --quiet",
        "test --warnings-as-errors"
      ],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"]
    ]
  end
end
