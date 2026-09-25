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
  format: "$time [$level] $metadata$message\n",
  metadata: [:request_id, :remote_ip, :user_id, :org_id, :params]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure to use UTC timestamp in tables
config :glific, Glific.Repo, migration_timestamps: [type: :utc_datetime]

# While we store everything in UTC, we need to respect the user's tz
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Configure Oban, its queues and crontab entries

oban_queues = [
  bigquery: [
    local_limit: 10,
    global_limit: [
      allowed: 1,
      burst: true,
      partition: [args: :organization_id]
    ]
  ],
  crontab: 10,
  default: [
    limit: 10,
    rate_limit: [allowed: 30, period: {1, :minute}, partition: [:worker, args: :organization_id]]
  ],
  dialogflow: 5,
  flow_wakeup: [
    local_limit: 20,
    global_limit: [
      allowed: 1,
      partition: [args: :organization_id]
    ]
  ],
  gcs: 10,
  gupshup: [
    local_limit: 20,
    global_limit: [
      allowed: 10,
      burst: false,
      partition: [args: :organization_id]
    ]
  ],
  webhook: [
    local_limit: 20,
    global_limit: [
      allowed: 3,
      burst: true,
      partition: [args: :organization_id]
    ]
  ],
  broadcast: 5,
  wa_group: 5,
  purge: 1,
  custom_certificate: [
    limit: 10,
    rate_limit: [allowed: 60, period: {1, :minute}, partition: [:worker, args: :organization_id]]
  ],
  gpt_webhook_queue: [
    local_limit: 20,
    global_limit: [
      allowed: 3,
      burst: true,
      partition: [args: :organization_id]
    ]
  ],
  contact_import_bulk: [
    local_limit: 10,
    global_limit: [
      allowed: 5,
      partition: [args: :organization_id]
    ]
  ],
  gupshup_high_tps: 10,
  clone_assistant: 5,
  gupshup_inbound: [
    local_limit: 30,
    global_limit: [
      allowed: 10,
      burst: false,
      partition: [args: :organization_id]
    ]
  ]
]

oban_crontab = [
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :contact_status}},
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :wakeup_flows}},
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :gcs}},
  {"*/2 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :bigquery}},
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :triggers_and_broadcast}},
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :check_user_job_status}},
  {"*/1 * * * *", Glific.Jobs.MinuteWorker, args: %{job: :poll_ai_evaluations}},
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

oban_engine = Oban.Pro.Engines.Smart

oban_plugins = [
  # Prune jobs after 5 mins, gives us some time to go investigate if needed
  {Oban.Pro.Plugins.DynamicPruner, mode: {:max_age, 5 * 60}, limit: 25_000},
  {Oban.Plugins.Cron, crontab: oban_crontab},
  Oban.Pro.Plugins.DynamicLifeline,
  # only reprioritizing for gpt_webhook_queue for now
  {Oban.Pro.Plugins.DynamicPrioritizer,
   after: :infinity, queue_overrides: [gpt_webhook_queue: :timer.minutes(5)]}
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
    {Tesla.Adapter.Hackney,
     ssl_options: [{:middlebox_comp_mode, false}, {:verify, :verify_none}],
     pool: :glific_default_pool,
     connect_timeout: 5_000}

# Every rate limit in the application, grouped by the surface it guards. Glific.RateLimit reads
# these by name and raises if one is missing, so a limit can never quietly stop limiting.
config :glific,
  # Requests that match no route at all, per address.
  rate_limit_api_global: [scale_ms: 60_000, count: 60],
  # Per signed-in user, across the whole API.
  rate_limit_api_authenticated: [scale_ms: 60_000, count: 180],
  # Per address, across every unauthenticated endpoint. Offices sit behind one egress.
  rate_limit_api_unauthenticated: [scale_ms: 60_000, count: 300],
  # Charged in addition to the address, so rotating phone numbers buys nothing.
  rate_limit_api_phone: [scale_ms: 60_000, count: 300],
  # Staff registration OTP, per phone.
  rate_limit_api_otp: [scale_ms: 30_000, count: 1]

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
    Glific.Contacts.Contact,
    Glific.Flows.Flow,
    Glific.Partners.Credential,
    Glific.Triggers.Trigger,
    Glific.WhatsappForms.WhatsappForm,
    Glific.Assistants.Assistant,
    Glific.Assistants.AssistantConfigVersion,
    Glific.Assistants.KnowledgeBaseVersion
  ],
  primitive_structs: [
    DateTime
  ]

# The web channel is embedded on public sites, where a school, office or carrier NAT fronts many
# unrelated beneficiaries on one address, so its per-address budgets are far looser than the API's.
config :glific,
  # Its four public HTTP endpoints, per address.
  rate_limit_web_channel_api: [scale_ms: 60_000, count: 1200],
  # Sign-in OTP per phone. This, not the address budget, is the anti-enumeration control.
  rate_limit_web_channel_otp_phone: [scale_ms: 30_000, count: 1],
  # Its per-address companion. A computer lab signing a class in at once must not be refused.
  rate_limit_web_channel_otp_ip: [scale_ms: 60_000, count: 100],
  # Inbound socket messages, per contact.
  rate_limit_web_channel_message: [scale_ms: 10_000, count: 20],
  # Socket connects, charged before the token is verified so a flood cannot make us do the work.
  rate_limit_web_channel_connect_ip: [scale_ms: 60_000, count: 120],
  # What the node will accept at all. Past this, connects are refused as server busy.
  rate_limit_web_channel_connect_total: [scale_ms: 60_000, count: 1000],
  # Signed upload URLs. Each is a writable grant into the organization's bucket, so there is a
  # total across everybody too: no per-contact or per-address budget bounds storage abuse when
  # many contacts are driven at once.
  rate_limit_web_channel_upload_contact: [scale_ms: 60_000, count: 6],
  rate_limit_web_channel_upload_ip: [scale_ms: 60_000, count: 60],
  rate_limit_web_channel_upload_total: [scale_ms: 60_000, count: 120]

config :mime, :types, %{
  "audio/amr" => ["amr"],
  "audio/mp4" => ["m4a"],
  "audio/ogg" => ["oga", "ogg"],
  "video/3gpp" => ["3gp", "3gpp"]
}

config :glific, Glific.AI,
  model: "anthropic:claude-haiku-4-5",
  # Routing a question to a skill is a one-word answer, so it is pinned to the
  # cheapest model rather than following whatever answers the question. Without
  # this, upgrading `model` would silently make every classification cost more.
  classifier_model: "anthropic:claude-haiku-4-5",
  max_tokens: 4_096,
  receive_timeout: 60_000

# What bounds one question. Nothing in a model's control flow stops it looping,
# so these are the circuit breaker: whichever is reached first ends the run and
# records why.
config :glific, Glific.AI.Agent,
  max_run_steps: 12,
  max_run_cost_usd: "0.50",
  max_run_duration_ms: 120_000

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
