# In this file, we load all configuration and secrets from environment variables.
# Added few checks for debug.
# This file is now used for all releases

import Config
import Dotenvy

source(["config/.env", "config/.env.#{config_env()}"])

ssl_port = env("SSL_PORT", :integer, 443)
http_port = env("HTTP_PORT", :integer, 4000)

config :glific, Glific.Repo,
  url: env!("DATABASE_URL", :string!),
  pool_size: env("POOL_SIZE", :integer, 20),
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

config :glific, :max_rate_limit_request, env("MAX_RATE_LIMIT_REQUEST", :integer, 180)

# AppSignal configs
config :appsignal, :config,
  otp_app: :glific,
  name: "Glific",
  hostname: env!("APPSIGNAL_HOSTNAME", :string),
  active: env("APPSIGNAL_ACTIVE", :boolean, false),
  revision: Application.spec(:glific, :vsn) |> to_string(),
  push_api_key: env!("APPSIGNAL_PUSH_API_KEY", :string!)

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
