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
  bigquery: 5,
  crontab: 10,
  default: 10,
  dialogflow: 5,
  gcs: 5,
  gupshup: 10,
  webhook: 10,
  broadcast: 5
]

oban_crontab = [
  {"*/5 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :contact_status}},
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :wakeup_flows}},
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :bigquery}},
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :triggers_and_broadcast}},
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :gcs}},
  {"0 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :stats}},
  {"1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :hourly_tasks}},
  {"2 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :delete_tasks}},
  {"58 23 * * *", Glific.Jobs.MinuteWorker, args: %{job: :daily_tasks}},
  {"*/5 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :five_minute_tasks}},
  {"0 0 * * *", Glific.Jobs.MinuteWorker, args: %{job: :update_hsms}}
]

oban_engine = Oban.Pro.Queue.SmartEngine

oban_plugins = [
  # Prune jobs after 60 mins, gives us some time to go investigate if needed
  {Oban.Pro.Plugins.DynamicPruner, mode: {:max_age, 60 * 60}, limit: 25_000},
  {Oban.Plugins.Cron, crontab: oban_crontab},
  Oban.Pro.Plugins.Lifeline,
  Oban.Web.Plugins.Stats,
  Oban.Plugins.Gossip
]

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

config :waffle,
  storage: Waffle.Storage.Google.CloudStorage,
  token_fetcher: Glific.GCS

config :esbuild,
  version: "0.14.0",
  default: [
    args: ~w(js/app.js --bundle --target=es2016 --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :glific, Glific.Communications.Mailer, adapter: Swoosh.Adapters.AmazonSES

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
