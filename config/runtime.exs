# In this file, we load all configuration and secrets from environment variables.
# Added few checks for debug.
# This file is now used for all releases

import Config
import Dotenvy

source(["config/.env", "config/.env.#{config_env()}", System.get_env()])

ssl_port = env!("SSL_PORT", :integer, 443)
http_port = env!("HTTP_PORT", :integer, 4000)

config :glific, Glific.Repo,
  url: env!("DATABASE_URL", :string!),
  pool_size: env!("POOL_SIZE", :integer, 20),
  show_sensitive_data_on_connection_error: true,
  prepare: :named,
  parameters: [plan_cache_mode: "force_custom_plan"]

check_origin = [env!("REQUEST_ORIGIN", :string!), env!("REQUEST_ORIGIN_WILDCARD", :string!)]

# Glific endpoint configs
config :glific, GlificWeb.Endpoint,
  server: true,
  http: [:inet6, port: http_port],
  check_origin: check_origin,
  secret_key_base: env!("SECRET_KEY_BASE", :string!),
  url: [host: env!("BASE_URL", :string!)],
  render_errors: [view: GlificWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Glific.PubSub,
  live_view: [signing_salt: env!("SIGNING_SALT", :string!)]

config :glific,
  auth_username: env!("AUTH_USERNAME", :string!),
  auth_password: env!("AUTH_PASSWORD", :string!)

config :glific, :max_rate_limit_request, env!("MAX_RATE_LIMIT_REQUEST", :integer, 180)

# AppSignal configs
config :appsignal, :config,
  otp_app: :glific,
  name: "Glific",
  hostname: env!("APPSIGNAL_HOSTNAME", :string),
  active: env!("APPSIGNAL_ACTIVE", :boolean, false),
  revision: Application.spec(:glific, :vsn) |> to_string(),
  push_api_key: env!("APPSIGNAL_PUSH_API_KEY", :string!),
  ecto_repos: [],
  ignore_namespaces: ["gupshup_webhooks", "gupshup_enterprise_webhooks", "flow_editor_controller"],
  instrument_oban: false

config :glific, Glific.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V3", key: Base.decode64!(env!("CIPHER_KEY", :string))},
    old_key:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V2", key: Base.decode64!(env!("OLD_CIPHER_KEY", :string))}
  ]

config :stripity_stripe,
  api_key: env!("STRIPE_API_KEY", :string!),
  signing_secret: env!("STRIPE_SIGNING_SECRET", :string!)

config :glific, Glific.Communications.Mailer,
  region: env!("SES_REGION", :string!, "This is not a region"),
  access_key: env!("SES_KEY", :string!, "This is not a key"),
  secret: env!("SES_SECRET", :string!, "This is not a secret")

config :glific,
  google_captcha_secret_key: env!("RECAPTCHA_SECRET_KEY", :string!, "This is not a secret")

config :glific,
  gcs_file_count: env!("GCS_FILE_COUNT", :integer, 5),
  broadcast_contact_count: env!("BROADCAST_CONTACT_COUNT", :integer, 100)

config :glific,
  open_ai: env!("OPEN_AI_KEY", :string!, "This is not a secret")

config :glific,
  google_translate: env!("GOOGLE_TRANSLATE_KEY", :string!, "This is not a secret")

config :glific,
  notion_secret: env!("NOTION_SECRET", :string!, "This is not a secret")

config :glific,
  gigalixir_username: env!("GIGALIXIR_USERNAME", :string!, "This is not a secret")

config :glific,
  gigalixir_api_key: env!("GIGALIXIR_API_KEY", :string!, "This is not a secret")

config :glific,
  gigalixir_app_name: env!("GIGALIXIR_APP_NAME", :string!, "This is not a secret")

config :glific,
  bhasini_user_id: env!("BHASINI_USER_ID", :string!, "This is not a secret")

config :glific,
  bhasini_ulca_api_key: env!("BHASINI_ULCA_API_KEY", :string!, "This is not a secret")

config :glific,
  bhasini_inference_key: env!("BHASINI_INFERENCE_KEY", :string!, "This is not a secret")

config :glific,
  google_maps_api_key: env!("GOOGLE_MAPS_API_KEY", :string!, "This is not a secret")

config :glific,
  ERP_API_KEY: env!("ERP_API_KEY", :string!, "This is not the ERP API key"),
  ERP_SECRET: env!("ERP_SECRET", :string!, "This is not the ERP secret")

config :glific,
  open_ai_project: env!("OPEN_AI_PROJECT", :string!, "This is not a secret")

config :glific,
  avni_password: env!("AVNI_PASSWORD", :string!, "This is not a secret")

config :glific, Glific.Erase,
  msg_delete_batch_size: env!("MSG_DELETE_BATCH_SIZE", :integer, 100_000),
  max_msg_rows_to_delete: env!("MAX_MSG_ROWS_TO_DELETE", :integer, 2_000_000)

# Percent of total job metrics to be sent to appsignal
config :glific,
  appsignal_sampling_rate: env!("APPSIGNAL_SAMPLING_RATE", :integer, 10)
