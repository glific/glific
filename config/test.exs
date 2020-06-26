use Mix.Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :glific, Glific.Repo,
  username: "postgres",
  password: "postgres",
  database: "glific_test#{System.get_env("MIX_TEST_PARTITION")}",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :glific, GlificWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

# setting the state of the environment for use within code base
config :glific, :environment, :test

config :glific, Oban, crontab: false, queues: false, prune: :disabled

config :glific,
  provider: Glific.Providers.Gupshup,
  provider_id: "gupshup-provider-23",
  provider_limit: 10

config :tesla, adapter: Tesla.Mock

config :phoenix, :json_library, Jason

config :pow, Pow.Ecto.Schema.Password, iterations: 1

# There is an issue with CI, Will move this to test.secret.exs in the future
# import_config "test.secret.exs"
config :glific,
  provider_url: "https://api.gupshup.io/sm/api/v1",
  provider_key: "abcdefghigklmnop"
