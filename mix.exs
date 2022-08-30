defmodule Glific.MixProject do
  use Mix.Project

  @github_url "https://github.com/glific/glific/"
  @home_url "https://glific.io"
  @test_envs [:test, :test_full]
  @oban_envs [:prod, :dev] ++ @test_envs
  # comment above line
  # ifyou dont have Oban pro license, this is your best hack
  # uncomment below line
  # @oban_envs [:prod]

  def project do
    [
      app: :glific,
      version: "4.6.4",
      elixir: "~> 1.13",
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
      compilers: [:phoenix] ++ Mix.compilers(),
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
        test_full: :test
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
      {:phoenix, "~> 1.6"},
      {:phoenix_ecto, "~> 4.1"},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_live_reload, "~> 1.2", only: [:dev | @test_envs]},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix_live_view, "~> 0.17"},
      {:phoenix_live_dashboard, "~> 0.5"},
      {:telemetry, "~> 1.0"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:ecto_sql, "~> 3.8"},
      {:ecto_psql_extras, "~> 0.2"},
      {:esbuild, "~> 0.2", runtime: Mix.env() == :dev},
      {:postgrex, "~> 0.16"},
      {:floki, ">= 0.27.0", only: @test_envs},
      {:gettext, "~> 0.20"},
      {:decimal, "~> 2.0"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.0"},
      {:ecto_enum, "~> 1.4"},
      {:pow, "~> 1.0.24"},
      {:dialyxir, "~> 1.2", only: [:dev | @test_envs], runtime: false},
      {:credo, "~> 1.6", only: [:dev | @test_envs], runtime: false},
      {:ex_doc, "~> 0.22", only: [:dev | @test_envs], runtime: false},
      {:inch_ex, "~> 2.0", only: [:dev | @test_envs], runtime: false},
      {:doctor, "~> 0.19"},
      {:httpoison, "~> 1.8"},
      {:poison, "~> 4.0"},
      {:ex_rated, "~> 2.0"},
      {:absinthe, "~> 1.5"},
      {:absinthe_plug, "~> 1.5"},
      {:absinthe_phoenix, "~> 2.0"},
      {:dataloader, "~> 1.0"},
      {:hackney, "~> 1.17"},
      {:tesla, "~> 1.4"},
      {:oban, "~> 2.12"},
      {:oban_web, "~> 2.9", organization: "oban", only: @oban_envs},
      {:oban_pro, "~> 0.12", organization: "oban", only: @oban_envs},
      {:faker, "~> 0.13"},
      {:mock, "~> 0.3", only: [:dev | @test_envs]},
      {:excoveralls, "~> 0.14", only: @test_envs},
      {:publicist, "~> 1.1"},
      {:cors_plug, "~> 3.0"},
      {:ex_check, "~> 0.12", only: [:dev | @test_envs], runtime: false},
      {:sobelow, "~> 0.8", only: [:dev | @test_envs]},
      {:goth, "~> 1.3"},
      {:wormwood, "~> 0.1"},
      {:timex, "~> 3.7"},
      {:slugify, "~> 1.3"},
      {:cachex, "~> 3.2"},
      {:fun_with_flags, "~> 1.9"},
      {:fun_with_flags_ui, "~> 0.8"},
      {:passwordless_auth, "~> 0.3.0"},
      {:appsignal_phoenix, "~> 2.1"},
      {:poolboy, "~> 1.5"},
      {:phil_columns, git: "https://github.com/glific/phil_columns-ex.git", branch: "dev"},
      {:cloak_ecto, "~> 1.2"},
      {:google_api_big_query, "~> 0.47"},
      {:google_api_dialogflow, "~> 0.62"},
      {:google_api_sheets, "~> 0.29"},
      {:waffle, "~> 1.1"},
      {:waffle_gcs, git: "https://github.com/glific/waffle_gcs"},
      {:waffle_ecto, "~> 0.0"},
      {:csv, "~> 2.4"},
      {:observer_cli, "~> 1.6"},
      {:apiac_filter_ip_whitelist, "~> 1.0"},
      {:ex_phone_number, "~> 0.3"},
      {:tzdata, "~> 1.1"},
      {:stripity_stripe, "~> 2.10"},
      {:stripe_mock, "~> 0.1", only: @test_envs},
      {:remote_ip, "~> 1.0"},
      {:exvcr, "~> 0.13", only: @test_envs},
      {:dotenvy, "~> 0.1"},
      {:phoenix_swoosh, "~> 1.0"},
      {:gen_smtp, "~> 1.1"}
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
        "ecto.migrate",
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
        "ecto.migrate",
        "phil_columns.seed --tenant glific",
        "test"
      ],
      test: ["ecto.create --quiet", "ecto.migrate", "test"],
      "assets.deploy": ["esbuild default --minify", "phx.digest"]
    ]
  end
end
