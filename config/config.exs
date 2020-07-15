# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :glific,
  ecto_repos: [Glific.Repo],
  provider: Glific.Providers.Gupshup.Message,
  provider_worker: Glific.Providers.Gupshup.Worker,
  # deprovider_worker: Glific.Providers.Glifproxy.Worker,
  provider_id: "gupshup-provider-23",
  provider_limit: 10

# Configures the endpoint
config :glific, GlificWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "IN3UOAXU/FC6yPcBcC/iHg85F52QYPvjSiDkRdoydEobrrL+aNhat5I5+WA4IW0e",
  render_errors: [view: GlificWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Glific.PubSub,
  live_view: [signing_salt: "Xz6dQndd"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure to use UTC timestamp in tables
config :glific,
       Glific.Repo,
       migration_timestamps: [type: :utc_datetime]

config :glific, Oban,
  repo: Glific.Repo,
  prune: {:maxlen, 10_000},
  queues: [default: 10, gupshup: 10, glifproxy: 10, webhook: 10]

config :tesla, adapter: Tesla.Adapter.Hackney

config :glific, :pow,
  user: Glific.Users.User,
  repo: Glific.Repo

config :passwordless_auth,
  sms_adapter: Glific.Providers.Gupshup

# Sentry configuration

# configure sentry's logger
config :logger,
  backends: [:console, Sentry.LoggerBackend]

config :sentry,
  dsn: "https://4ae43f4bc3c14881aace7956eb4a0b64@o412613.ingest.sentry.io/5290153",
  environment_name: Mix.env(),
  enable_source_code_context: true,
  root_source_code_path: File.cwd!(),
  tags: %{
    env: "dev"
  },
  included_environments: [:prod]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
