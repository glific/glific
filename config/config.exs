# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :glific,
  ecto_repos: [Glific.Repo],
  provider: Glific.Providers.Gupshup,
  provider_id: "gupshup-provider-23",
  provider_limit: 10,
  message_ancestors_limit: 75

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
  queues: [default: 10, gupshup: 10, webhook: 10]

# queues: nil

config :tesla, adapter: Tesla.Adapter.Hackney

config :glific, :pow,
  user: Glific.Users.User,
  repo: Glific.Repo

config :passwordless_auth,
  # seconds; optional (defaults to 30 if not provided)
  garbage_collector_frequency: 30,
  # optional (defaults to 5 if not provided)
  num_attempts_before_timeout: 5,
  # seconds; optional (defaults to 60 if not provided)
  rate_limit_timeout_length: 60,
  # seconds, optional (defaults to 300 if not provided)
  verification_code_ttl: 300

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
