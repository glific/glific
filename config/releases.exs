# In this file, we load production configuration and secrets from environment variables.
# Added few checks for debug.
# This file will be used for production release only.
import Config

db_url =
  System.get_env("DATABASE_URL") ||
    raise """
    environment variable DATABASE_URL is missing
    """

ssl_port = System.get_env("SSL_PORT") || 443
http_port = System.get_env("HTTP_PORT") || 4000

config :glific, Glific.Repo,
  url: db_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  show_sensitive_data_on_connection_error: true,
  prepare: :named,
  parameters: [plan_cache_mode: "force_custom_plan"]

secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    raise """
    environment variable SECRET_KEY_BASE is missing.
    You can generate one by calling: mix phx.gen.secret
    """

check_origin =
  [System.get_env("REQUEST_ORIGIN"), System.get_env("REQUEST_ORIGIN_WILDCARD")] ||
    raise """
    environment variable REQUEST_ORIGIN/REQUEST_ORIGIN_WILDCARD is missing.
    """

# GLific endpoint configs
config :glific, GlificWeb.Endpoint,
  server: true,
  http: [:inet6, port: http_port],
  check_origin: check_origin,
  secret_key_base: secret_key_base,
  url: [host: System.get_env("BASE_URL")]

auth_username =
  System.get_env("AUTH_USERNAME") ||
    raise """
    environment variable AUTH_USERNAME is missing.
    """

auth_password =
  System.get_env("AUTH_PASSWORD") ||
    raise """
    environment variable AUTH_PASSWORD is missing.
    """

config :glific,
  auth_username: auth_username,
  auth_password: auth_password

# both these variables will go into the saas table coming in Glific v1.5
saas_phone =
  System.get_env("SAAS_PHONE") ||
  raise """
  environment variable SAAS_PHONE is missing.
  """

# The SaaS Admin root account phone number
config :glific, :saas_phone, System.get_env("SAAS_PHONE")

saas_organization_id =
  System.get_env("SAAS_ORGANIZATION_ID") ||
  raise """
  environment variable SAAS_PHONE is missing.
  """

# The SaaS Admin root account phone number
config :glific, :saas_organization_id, System.get_env("SAAS_PHONE")

config :glific, :max_rate_limit_request, System.get_env("MAX_RATE_LIMIT_REQUEST")

# AppSignal configs
config :appsignal, :config,
  otp_app: :glific,
  name: "Glific",
  # we need to make this dynamic at some point
  hostname: System.get_env("APPSIGNAL_HOSTNAME"),
  active: true,
  revision: Application.spec(:glific, :vsn) |> to_string(),
  push_api_key: System.get_env("APPSIGNAL_PUSH_API_KEY")

config :glific, Glific.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V3", key: Base.decode64!(System.get_env("CIPHER_KEY"))},
    old_key:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V2", key: Base.decode64!(System.get_env("OLD_CIPHER_KEY"))}
  ]

# All these stripe ids will go into the saas table coming in Glific v1.5
config :glific,
  stripe_ids: [
    product: System.get_env("STRIPE_PRODUCT_ID"),
    setup: System.get_env("STRIPE_SETUP_ID"),
    monthly: System.get_env("STRIPE_MONTHLY_ID"),
    users: System.get_env("STRIPE_USERS_ID"),
    messages: System.get_env("STRIPE_MESSAGES_ID"),
    consulting_hours: System.get_env("STRIPE_CONSULTING_HOURS_ID")
  ]

config :stripity_stripe,
  api_key: System.get_env("STRIPE_API_KEY"),
  signing_secret: System.get_env("STRIPE_SIGNING_SECRET")
