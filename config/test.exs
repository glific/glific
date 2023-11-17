import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :pbkdf2_elixir, :rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :glific, Glific.Repo, pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :glific, GlificWeb.Endpoint,
  http: [port: 4002],
  url: [host: "glific.test"],
  server: false

# Print only warnings and errors during test
config :logger,
  level: :emergency,
  compile_time_purge_matching: [[level_lower_than: :emergency]]

# setting the state of the environment for use within code base
config :glific, :environment, :test

config :glific, Oban,
  prefix: "global",
  crontab: false,
  log: :debug,
  testing: :manual

config :glific,
  provider: Glific.Providers.Gupshup.Message,
  provider_worker: Glific.Providers.Gupshup.Worker,
  provider_id: "gupshup-provider-23",
  provider_limit: 10

config :goth, disabled: true

config :glific, Poolboy, worker: Glific.Processor.ConsumerWorkerMock

config :tesla, adapter: Tesla.Mock

config :phoenix, :json_library, Jason

config :pow, Pow.Ecto.Schema.Password, iterations: 1

config :appsignal, :config,
  otp_app: :glific,
  active: false,
  env: :test

# There is an issue with CI, Will move this to test.secret.exs in the future
# import_config "test.secret.exs"
config :glific,
  provider_url: "https://api.gupshup.io/sm/api/v1",
  provider_key: "random_abcdefghigklmnop"

config :glific,
  stripe_ids: [
    setup: "random_price_1IlrYwEMShkCsLFnxKbdGV79",
    monthly: %{
      product: "random_prod_JG5ns5",
      inactive: "random_price_1IfMxsEMShkCs",
      monthly: "random_price_1IfMurEMShkC",
      users: "random_price_1IfNdDEMShk",
      messages: "random_price_1IfNf2EMSh",
      consulting_hours: "random_price_1IfNe9EMShk"
    },
    quarterly: %{
      product: "random_prod_N11hy4EQ5YbJNd",
      quarterly: "random_price_1MGzdvEMShkCsLFninxSY6iZ"
    }
  ]

config :glific, Glific.Communications.Mailer, adapter: Swoosh.Adapters.Test
