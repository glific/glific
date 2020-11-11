import Config

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
  url: [host: "glific.test"],
  server: false

# Print only warnings and errors during test
config :logger,
  level: :warn

# setting the state of the environment for use within code base
config :glific, :environment, :test

config :glific, Oban,
  prefix: "global",
  crontab: false,
  queues: false,
  plugins: false

config :glific,
  provider: Glific.Providers.Gupshup.Message,
  provider_worker: Glific.Providers.Gupshup.Worker,
  provider_id: "gupshup-provider-23",
  provider_limit: 10

config :glific, Poolboy, worker: Glific.Processor.ConsumerWorkerMock

config :tesla, adapter: Tesla.Mock

config :phoenix, :json_library, Jason

config :pow, Pow.Ecto.Schema.Password, iterations: 1

# There is an issue with CI, Will move this to test.secret.exs in the future
# import_config "test.secret.exs"
config :glific,
  provider_url: "https://api.gupshup.io/sm/api/v1",
  provider_key: "abcdefghigklmnop"

config :appsignal, :config,
  active: false,
  env: :test

config :glific, Glific.Vault,
  cloak_repo: [Glific.Repo],
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1", key: Base.decode64!("BliS4zyqMG065ZrRJ8BhhruZFXnpV+eYAQBRqzusnSY=")}
  ]
