import Config

# setting the state of the environment for use within code base
config :glific, :environment, :dev

# PROTOTYPE: bypasses real SMS OTP delivery/verification for the public web channel auth
# endpoint (accepts a hardcoded "9999" OTP). Remove once real SMS OTP lands. Must stay false
# (unset) in config/prod.exs and config/runtime.exs.
config :glific, web_channel_otp_bypass: true

# PROTOTYPE: when an org has no Google Cloud Storage credential, web-channel media uploads fall
# back to writing under priv/static/uploads and serving them via Plug.Static, so audio/video/file
# work locally without GCS. Must stay false (unset) in config/prod.exs and config/runtime.exs.
config :glific, web_channel_local_media: true

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with webpack to recompile .js and .css sources.
config :glific, GlificWeb.Endpoint,
  # EXPERIMENT TO get everyone to switch to https even for local development
  # So we can record audio etc, which requires ssl
  https: [
    port: 4001,
    cipher_suite: :strong,
    certfile: "priv/cert/glific.test+1.pem",
    keyfile: "priv/cert/glific.test+1-key.pem"
  ],
  debug_errors: true,
  code_reloader: true,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}
  ]

# Preview/hosted deploys (e.g. Bunnyshell): the frontends live on different hostnames than
# the backend and reach it directly (no Vite proxy). BACKEND_HOST sets the endpoint host so
# GlificWeb.SubdomainPlug resolves the default "glific" org, and CHECK_ORIGIN allow-lists the
# frontends' origins so their WebSocket handshakes are accepted. Absent these vars, local dev
# behaves exactly as before.
if backend_host = System.get_env("BACKEND_HOST") do
  config :glific, GlificWeb.Endpoint,
    url: [host: backend_host, scheme: "https", port: 443],
    check_origin: String.split(System.get_env("CHECK_ORIGIN", ""), ",", trim: true),
    http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4000"))]

  config :glific, Glific.Repo,
    hostname: System.get_env("DATABASE_HOST", "localhost"),
    username: System.get_env("DATABASE_USER", "postgres"),
    password: System.get_env("DATABASE_PASSWORD", "postgres"),
    database: System.get_env("DATABASE_NAME", "glific_dev"),
    port: String.to_integer(System.get_env("DATABASE_PORT", "5432"))
end

# config :absinthe, Absinthe.Logger,
#   pipeline: true,
#   level: :debug

# Watch static and templates for browser reloading.
config :glific, GlificWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/glific_web/(live|views)/.*(ex)$",
      ~r"lib/glific_web/templates/.*(eex)$"
    ]
  ]

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :appsignal, :config,
  otp_app: :glific,
  active: false,
  env: :dev

config :glific, Glific.Communications.Mailer, adapter: Swoosh.Adapters.Local

import_config "dev.secret.exs"
