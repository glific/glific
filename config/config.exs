# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :glific,
  ecto_repos: [Glific.Repo],
  dialogflow_url: "https://dialogflow.clients6.google.com",
  dialogflow_project_id: "small-talk-talnvm",
  dialogflow_project_email: "elixirclient@small-talk-talnvm.iam.gserviceaccount.com"

# Configures the endpoint
config :glific, GlificWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "IN3UOAXU/FC6yPcBcC/iHg85F52QYPvjSiDkRdoydEobrrL+aNhat5I5+WA4IW0e",
  render_errors: [view: GlificWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Glific.PubSub,
  live_view: [signing_salt: "Xz6dQndd"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure to use UTC timestamp in tables
config :glific,
       Glific.Repo,
       migration_timestamps: [type: :utc_datetime]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
