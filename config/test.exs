import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :pbkdf2_elixir, :rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :glific, Glific.Repo, pool: Ecto.Adapters.SQL.Sandbox

# Print only warnings and errors during test. :info and above are kept at compile time so
# tests can raise the level and assert on a log line with ExUnit.CaptureLog.
config :logger,
  level: :emergency,
  compile_time_purge_matching: [[level_lower_than: :info]]

# setting the state of the environment for use within code base
config :glific, :environment, :test

# The index lives in Cachex, which outlives a test's sandbox rollback, so writes do not rebuild it
# by default. A test that wants the production behaviour turns this on for its duration.
config :glific, :refresh_organization_index, false

# Rate limits are defined in config/runtime.exs, which raises them out of the suite's way under
# :test. A test that wants one to fire sets it with Application.put_env/3 for its own duration.

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

config :glific, open_ai: "sk-test_api_key"

config :glific, Glific.ThirdParty.Superset.ApiClient,
  base_url: "https://moonshine.projecttech4dev.org/api/v1",
  dashboard_id: "71f4c8d9-f9c6-4b9d-9b28-80c550681b7f",
  guest_username: "glific-dev-embed",
  username: "superset_username",
  password: "superset_password"

config :glific, gupshup_partner_client_secret: "test_client_secret"

# No org in the test suite has GCS credentials configured, so route web channel uploads to local
# disk instead — never enabled in dev/prod.
config :glific, :web_channel_local_media, true
