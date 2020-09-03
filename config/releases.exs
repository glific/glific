# In this file, we load production configuration and secrets from environment variables.
# Added few checks for debug.
# This file will be used for production release only.
import Config

db_host =
  System.get_env("DATABASE_HOST") ||
    raise """
    environment variable DATABASE_HOST is missing.
    """

db_database = System.get_env("DATABASE_DB") || "glific_prod"
db_username = System.get_env("DATABASE_USER") || "postgres"
db_password = System.get_env("DATABASE_PASSWORD") || "postgres"
db_url = "ecto://#{db_username}:#{db_password}@#{db_host}/#{db_database}"
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

config :glific, GlificWeb.Endpoint,
  server: true,
  http: [:inet6, port: http_port],
  check_origin: check_origin,
  secret_key_base: secret_key_base,
  url: [host: System.get_env("BASE_URL")]

config :glific,
  provider_url: System.get_env("PROVIDER_URL"),
  provider_key: System.get_env("PROVIDER_KEY")

config :appsignal, :config,
  name: "Glific",
  push_api_key: System.get_env("GLIFIC_PUSH_API_KEY")

# for now this is optional, so we check for file exists, need
# a more robust solution going forward
# goth_json = System.get_env("GOTH_JSON_CREDENTIALS") ||
#   raise """
#   environment variable GOTH_JSON_CREDENTIALS is missing.
#   """

goth_json = """
{
  "type": "#{System.get_env("GOTH_TYPE")}",
  "project_id": "#{System.get_env("GOTH_PROJECT_ID")}",
  "private_key_id": "#{System.get_env("GOTH_PRIVATE_KEY_ID")}",
  "private_key": "#{System.get_env("GOTH_PRIVATE_KEY")}",
  "client_email": "#{System.get_env("GOTH_CLIENT_EMAIL")}",
  "client_id": "#{System.get_env("GOTH_CLIENT_ID")}",
  "auth_uri": "#{System.get_env("GOTH_AUTH_URI")}",
  "token_uri": "#{System.get_env("GOTH_TOKEN_URI")}",
  "auth_provider_x509_cert_url": "#{System.get_env("GOTH_AUTH_PROVIDER_X509_CERT_URL")}",
  "client_x509_cert_url": "#{System.get_env("GOTH_CLIENT_X509_CERT_URL")}"
}
"""

# config goth
config :goth,
  json: goth_json