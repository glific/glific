import Config

# Do not print debug messages in production
config :logger, level: :info

# setting the state of the environment for use within code base
config :glific, :environment, :prod

# set the translator adapter
# Move this to dynamic per organization at a later stage
config :glific, :adaptors, translators: Glific.Flows.Translate.GoogleTranslate

# Compile-time only: Phoenix builds Plug.SSL into the endpoint, so this cannot move to runtime.exs.
# TLS ends at gigalixir's edge, hence x-forwarded-proto; host: nil keeps redirects on the org subdomain.
config :glific, GlificWeb.Endpoint, force_ssl: [rewrite_on: [:x_forwarded_proto], host: nil]

config :appsignal, :config,
  otp_app: :glific,
  active: true,
  env: :prod
