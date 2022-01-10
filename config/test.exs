import Config

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
  queues: false,
  log: :debug,
  plugins: false

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

# There is an issue with CI, Will move this to test.secret.exs in the future
# import_config "test.secret.exs"
config :glific,
  provider_url: "https://api.gupshup.io/sm/api/v1",
  provider_key: "random_abcdefghigklmnop"

config :glific,
  stripe_ids: [
    product: "random_prod_JG5ns5",
    setup: "random_price_1IfMxsEMShkCs",
    monthly: "random_price_1IfMurEMShkC",
    users: "random_price_1IfNdDEMShk",
    messages: "random_price_1IfNf2EMSh",
    consulting_hours: "random_price_1IfNe9EMShk"
  ]

config :glific, Glific.Communications.Mailer, adapter: Swoosh.Adapters.Test
