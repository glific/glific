import Config

# Do not print debug messages in production
config :logger, level: :info

# setting the state of the environment for use within code base
config :glific, :environment, :prod

config :appsignal, :config,
  otp_app: :glific,
  active: true,
  env: :prod
