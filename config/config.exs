# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :glific,
  ecto_repos: [Glific.Repo],
  global_schema: "global"

# Configures the endpoint
config :glific, GlificWeb.Endpoint,
  server: true,
  http: [port: 4000],
  # EXPERIMENT TO get everyone to switch to https even for local development
  # So we can record audio etc, which requires ssl
  # https: [
  #   port: 4000,
  #   cipher_suite: :strong,
  #   certfile: "priv/cert/glific.test+1.pem",
  #   keyfile: "priv/cert/glific.test+1-key.pem"
  # ],
  url: [host: "glific.test"],
  secret_key_base: "IN3UOAXU/FC6yPcBcC/iHg85F52QYPvjSiDkRdoydEobrrL+aNhat5I5+WA4IW0e",
  render_errors: [view: GlificWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Glific.PubSub,
  live_view: [signing_salt: "4htfH6BMHdxcuDKFHeSryT32amWvVvlX"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id, :org_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure to use UTC timestamp in tables
config :glific, Glific.Repo, migration_timestamps: [type: :utc_datetime]

# While we store everything in UTC, we need to respect the user's tz
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Configure Oban, its queues and crontab entries

oban_queues = [
  default: 10,
  gupshup: 10,
  webhook: 10,
  crontab: 10,
  bigquery: 5,
  gcs: 5
]

oban_crontab = [
  {"*/5 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :contact_status}},
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :wakeup_flows}},
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :bigquery}},
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :execute_triggers}},
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :gcs}},
  {"0 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :hourly_tasks}},
  {"3 0 * * *", Glific.Jobs.MinuteWorker, args: %{job: :daily_tasks}},
  {"*/5 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :five_minute_tasks}},
  {"0 0 * * *", Glific.Jobs.MinuteWorker, args: %{job: :update_hsms}}
]

oban_envs = [:prod, :dev, :test]

oban_engine =
  if Mix.env() in oban_envs,
    do: Oban.Pro.Queue.SmartEngine,
    else: Oban.Queue.BasicEngine

oban_plugins_prod =
  if Mix.env() in oban_envs,
    do: [
      Oban.Pro.Plugins.Lifeline,
      Oban.Web.Plugins.Stats,
      Oban.Plugins.Gossip
    ],
    else: []

oban_plugins =
  [
    # Prune jobs after 5 mins, gives us some time to go investigate if needed
    {Oban.Plugins.Pruner, max_age: 300},
    {Oban.Plugins.Cron, crontab: oban_crontab}
  ] ++ oban_plugins_prod

config :glific, Oban,
  prefix: "global",
  repo: Glific.Repo,
  engine: oban_engine,
  queues: oban_queues,
  plugins: oban_plugins

config :tesla, adapter: Tesla.Adapter.Hackney

config :glific, :max_rate_limit_request, 60

config :glific, :pow,
  user: Glific.Users.User,
  repo: Glific.Repo,
  users_context: Glific.Users,
  cache_store_backend: Pow.Store.Backend.MnesiaCache

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
# Note that we are setting global directly in the table name
config :fun_with_flags, :persistence,
  adapter: Glific.FunWithFlags.Store.Persistent.Ecto,
  repo: Glific.Repo,
  ecto_table_name: "fun_with_flags_toggles",
  ecto_prefix: "global"

config :fun_with_flags, :cache_bust_notifications,
  enabled: true,
  adapter: FunWithFlags.Notifications.PhoenixPubSub,
  client: Glific.PubSub

# config goth in default disabled state
config :goth,
  disabled: true

config :glific, Glific.Vault, ciphers: false

config :waffle,
  storage: Waffle.Storage.Google.CloudStorage,
  token_fetcher: Glific.GCS

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
