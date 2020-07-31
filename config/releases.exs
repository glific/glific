# In this file, we load production configuration and secrets from environment variables.
# Added few checks for debug.
# This file will be used for production release only.
import Config
db_host = System.get_env("DATABASE_HOST") || 
  raise """
  environment variable DATABASE_HOST is missing.
  """
db_database = System.get_env("DATABASE_DB") || "postgres" 
db_username = System.get_env("DATABASE_USER") || "postgres" 
db_password = System.get_env("DATABASE_PASSWORD") || "postgres"
db_url = "ecto://#{db_username}:#{db_password}@#{db_host}/#{db_database}"
ssl_port = System.get_env("SSL_PORT") || 444
config :glific, Glific.Repo,
  url:  db_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  show_sensitive_data_on_connection_error: true
secret_key_base = System.get_env("SECRET_KEY_BASE") ||
  raise """
  environment variable SECRET_KEY_BASE is missing.
  You can generate one by calling: mix phx.gen.secret
  """ 
config :glific, GlificWeb.Endpoint,
  server: true,
  http: [:inet6, port: 4000],
  https: [
    port: ssl_port,
    cipher_suite: :strong,
    keyfile: '/etc/letsencrypt/live/tides.coloredcow.com/privkey.pem',
    certfile: '/etc/letsencrypt/live/tides.coloredcow.com/cert.pem',
    cacertfile: '/etc/letsencrypt/live/tides.coloredcow.com/fullchain.pem'
  ],
  secret_key_base: secret_key_base,
  url: [host: System.get_env("BASE_URL")]
