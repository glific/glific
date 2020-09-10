# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :glific,
  ecto_repos: [Glific.Repo]

# Settings for gupshup, this should actually go in Provider database table or something
# similar
config :glific,
  provider: Glific.Providers.Gupshup.Message,
  provider_worker: Glific.Providers.Gupshup.Worker,
  provider_id: "gupshup",
  provider_limit: 10

# Configures the endpoint
config :glific, GlificWeb.Endpoint,
  url: [host: "glific.test"],
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

# While we store everything in UTC, we need to respect the user's tz
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Configure Oban, its queues and crontab entries
config :glific, Oban,
  repo: Glific.Repo,
  queues: [default: 10, dialogflow: 10, gupshup: 10, glifproxy: 10, webhook: 10, crontab: 10],
  crontab: [
    {"*/5 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :fun_with_flags}},
    {"*/5 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :contact_status}}
  ]

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

# phil columns to seed production data
config :phil_columns,
  ensure_all_started: ~w(timex)a

# FunWithFlags configuration.
config :fun_with_flags, :cache,
  enabled: true,
  # in seconds
  ttl: 900

# Use ecto.sql persistence adapter is the default, no need to set this.
config :fun_with_flags, :persistence,
  adapter: FunWithFlags.Store.Persistent.Ecto,
  repo: Glific.Repo,
  ecto_table_name: "fun_with_flags_toggles"

config :fun_with_flags, :cache_bust_notifications,
  enabled: true,
  adapter: FunWithFlags.Notifications.PhoenixPubSub,
  client: Glific.PubSub

# import the dialogflow config, splitting it up into a seperate file
# since we have some code in there to handle credentials
import_config "dialogflow.exs"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
