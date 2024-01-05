import Config

# Do not print debug messages in production
config :logger, level: :info

# setting the state of the environment for use within code base
config :glific, :environment, :prod

# set the translator adapter
# Move this to dynamic per organization at a later stage
config :glific, :adaptors, translators: Glific.Flows.Translate.OpenAI

config :appsignal, :config,
  otp_app: :glific,
  active: true,
  env: :prod
