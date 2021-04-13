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
  pool_size: 20,
  pool: Ecto.Adapters.SQL.Sandbox,
  prepare: :named,
  parameters: [plan_cache_mode: "force_custom_plan"]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :glific, GlificWeb.Endpoint,
  http: [port: 4002],
  url: [host: "glific.test"],
  server: false

# Print only warnings and errors during test
config :logger,
  # level: :debug
  level: :emergency,
  compile_time_purge_matching: [
    [level_lower_than: :emergency]
  ]

# setting the state of the environment for use within code base
config :glific, :environment, :test

# The SaaS Admin root account phone number
config :glific, :saas_phone, "+91111222333"

# config :absinthe, Absinthe.Logger,
#  pipeline: true,
#  level: :debug

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
  provider_key: "random_abcdefghigklmnop"

config :appsignal, :config,
  otp_app: :glific,
  active: false,
  env: :test

config :glific, Glific.Vault,
  cloak_repo: [Glific.Repo],
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1", key: Base.decode64!("BliS4zyqMG065ZrRJ8BhhruZFXnpV+eYAQBRqzusnSY=")}
  ]

config :glific,
stripe_ids: [
      product: "random_prod_JG5ns5",
      setup: "random_price_1IfMxsEMShkCs",
      monthly: "random_price_1IfMurEMShkC",
      users: "random_price_1IfNdDEMShk",
      messages: "random_price_1IfNf2EMSh",
      consulting_hours: "random_price_1IfNe9EMShk"
]

config :stripity_stripe,
  api_key:
    "random_sk_test_51HZXWAEMShkCsLFnX5gePfEYnt2czwXjNg92lD7cC",
  signing_secret: "random_whsec_F6xvua5ZhjS98FkK"
