# In this file, we load production configuration and secrets from environment variables.
# Added few checks for debug.
# This file will be used for production release only.
import Config

# db_host =
#   System.get_env("DATABASE_HOST") ||
#     raise """
#     environment variable DATABASE_HOST is missing.
#     """

# db_database = System.get_env("DATABASE_DB") || "glific_prod"
# db_username = System.get_env("DATABASE_USER") || "postgres"
# db_password = System.get_env("DATABASE_PASSWORD") || "postgres"
# db_url = "ecto://#{db_username}:#{db_password}@#{db_host}/#{db_database}"
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

# GLific endpoint configs
config :glific, GlificWeb.Endpoint,
  server: true,
  http: [:inet6, port: http_port],
  check_origin: false,
  secret_key_base: secret_key_base,
  url: [host: System.get_env("BASE_URL"), port: http_port]

# provider keys
config :glific,
  provider_key_1: System.get_env("PROVIDER_KEY_1"),
  provider_key_2: System.get_env("PROVIDER_KEY_2"),
  provider_key_3: System.get_env("PROVIDER_KEY_3"),
  provider_key_4: System.get_env("PROVIDER_KEY_4"),
  provider_key_5: System.get_env("PROVIDER_KEY_5")

# AppSignal configs
config :appsignal, :config,
  name: "Glific",
  push_api_key: System.get_env("APPSIGNAL_PUSH_API_KEY")

# Goth configs: Picking up json from env itself at run time
goth_json = System.get_env("GOTH_JSON_CREDENTIALS")

if goth_json !== nil do
  config :goth,
    json: goth_json,
    disabled: false
end

config :glific, Glific.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1", key: Base.decode64!(System.get_env("CIPHER_KEY"))}
  ]
