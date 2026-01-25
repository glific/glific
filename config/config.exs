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
config :logger, :default_formatter,
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
  bigquery: 10,
  crontab: 10,
  default: [limit: 10],
  dialogflow: 5,
  gcs: 10,
  gupshup: 10,
  webhook: 20,
  broadcast: 5,
  wa_group: 5,
  purge: 1,
  custom_certificate: [limit: 10],
  gpt_webhook_queue: 20,
  contact_import: 10,
  gupshup_high_tps: 10
]

oban_crontab = [
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :contact_status}},
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :wakeup_flows}},
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :gcs}},
  {"*/2 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :bigquery}},
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :triggers_and_broadcast}},
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :check_user_job_status}},
  {"0 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :stats}},
  {"1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :hourly_tasks}},
  {"2 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :delete_tasks}},
  {"58 23 * * *", Glific.Jobs.MinuteWorker, args: %{job: :daily_tasks}},
  {"0 3 * * *", Glific.Jobs.MinuteWorker, args: %{job: :tracker_tasks}},
  {"*/5 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :five_minute_tasks}},
  {"0 0 * * *", Glific.Jobs.MinuteWorker, args: %{job: :update_hsms}},
  # 21:00 Sat UTC is  02:30 SAT IST, running the msg purging a day before other DB purges
  # to test this in isolation
  {"0 21 * * FRI", Glific.Jobs.MinuteWorker, args: %{job: :weekly_message_purge}},
  # 21:00 Sat UTC is  02:30 Sun IST and hence low traffic
  {"0 21 * * SAT", Glific.Jobs.MinuteWorker, args: %{job: :weekly_tasks}},
  # We are sending report of previous week(MON to SUN)
  {"0 0 * * MON", Glific.Jobs.MinuteWorker, args: %{job: :weekly_report}},
  # {"0 0 1 * *", Glific.Jobs.MinuteWorker, args: %{job: :monthly_tasks}}
  # Syncing unsynced media files late in the night
  {"* 20-23 * * *", Glific.Jobs.MinuteWorker, args: %{job: :daily_low_traffic_tasks}}
]

oban_engine = Oban.Engines.Basic

oban_plugins = [
  # Prune jobs after 5 mins, gives us some time to go investigate if needed
  {Oban.Plugins.Pruner, max_age: 5 * 60, limit: 25_000},
  {Oban.Plugins.Cron, crontab: oban_crontab},
  Oban.Plugins.Lifeline
]

config :glific, Oban,
  prefix: "global",
  repo: Glific.Repo,
  engine: oban_engine,
  queues: oban_queues,
  plugins: oban_plugins,
  shutdown_grace_period: :timer.seconds(60)

# Adding ssl_options to fix #3037. However I dont understand this or the implications
# We will revisit it once we build a better understanding
config :tesla,
  adapter:
    {Tesla.Adapter.Hackney, ssl_options: [{:middlebox_comp_mode, false}, {:verify, :verify_none}]}

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
config :glific_phil_columns,
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

config :tailwind,
  version: "3.2.1",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

config :glific, Glific.Communications.Mailer, adapter: Swoosh.Adapters.AmazonSES
config :glific, :adaptors, translators: Glific.Flows.Translate.Simple

config :glific, secrets: []

config :ex_audit,
  ecto_repos: [Glific.Repo],
  version_schema: Glific.Version,
  tracked_schemas: [
    Glific.Flows.Flow,
    Glific.Partners.Credential,
    Glific.Triggers.Trigger,
    Glific.WhatsappForms.WhatsappForm
  ],
  primitive_structs: [
    DateTime
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
