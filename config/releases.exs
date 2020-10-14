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
  show_sensitive_data_on_connection_error: true

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

# AppSignal configs
config :appsignal, :config,
  name: "Glific",
  # we need to make this dynamic at some point
  hostname: "Glific Gigalixir",
  active: true,
  revision: Application.spec(:glific, :vsn) |> to_string(),
  push_api_key: System.get_env("APPSIGNAL_PUSH_API_KEY")

config :glific, Glific.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1", key: Base.decode64!(System.get_env("CIPHER_KEY"))}
  ]
