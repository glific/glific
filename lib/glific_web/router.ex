defmodule GlificWeb.Router do
  @moduledoc """
  a default gateway for all the external requests
  """
  use GlificWeb, :router
  @dialyzer {:nowarn_function, __checks__: 0}
  use Plug.ErrorHandler
  use Appsignal.Plug

  import Oban.Web.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {GlificWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug Pow.Plug.Session, otp_app: :glific
  end

  scope path: "/feature-flags" do
    # ensure that this is protected once we have authentication in place
    pipe_through [:browser, :auth]
    forward "/", FunWithFlags.UI.Router, namespace: "feature-flags"
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug GlificWeb.APIAuthPlug, otp_app: :glific
    plug GlificWeb.RateLimitPlug
    # plug :debug_response
  end

  pipeline :api_protected do
    plug Pow.Plug.RequireAuthenticated, error_handler: GlificWeb.APIAuthErrorHandler
    plug GlificWeb.ContextPlug
  end

  pipeline :auth_protected do
    plug :auth
  end

  scope "/api/v1", GlificWeb.API.V1, as: :api_v1 do
    pipe_through :api

    resources "/registration", RegistrationController, singleton: true, only: [:create]
    post "/registration/send-otp", RegistrationController, :send_otp
    post "/registration/reset-password", RegistrationController, :reset_password
    resources "/session", SessionController, singleton: true, only: [:create, :delete]
    post "/session/renew", SessionController, :renew
  end

  scope "/", GlificWeb do
    pipe_through [:browser, :auth]

    live "/", PageLive, :index
  end

  scope "/" do
    pipe_through [:browser, :auth]

    oban_dashboard("/oban")
  end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  import Phoenix.LiveDashboard.Router

  scope "/" do
    pipe_through [:browser, :auth]
    live_dashboard "/dashboard", metrics: GlificWeb.Telemetry, ecto_repos: [Glific.Repo]
  end

  # Custom stack for Absinthe
  scope "/" do
    pipe_through [:api, :api_protected]

    forward "/api", Absinthe.Plug, schema: GlificWeb.Schema

    forward "/graphiql", Absinthe.Plug.GraphiQL,
      schema: GlificWeb.Schema,
      interface: :simple,
      socket: GlificWeb.UserSocket
  end

  # pipeline :gupshup do
  #   plug APIacFilterIPWhitelist,
  #     whitelist: [
  #       # Whitelisting IP of localhost
  #       "127.0.0.0/8",
  #       # Whitelisting IP of Gigalixir
  #       "35.226.132.161/32",
  #       # Whitelisting IP of Gupshup
  #       "34.202.224.208/1",
  #       "52.66.99.126/1"
  #     ]
  # end

  scope "/", GlificWeb do
    # pipe_through :gupshup
    forward("/gupshup", Providers.Gupshup.Plugs.Shunt)
  end

  scope "/webhook/stripe" do
    post "/", StripeController, :stripe_webhook
  end

  scope "/flow-editor", GlificWeb.Flows do
    get "/globals", FlowEditorController, :globals

    get "/groups", FlowEditorController, :groups
    post "/groups", FlowEditorController, :groups_post

    get "/fields", FlowEditorController, :fields
    post "/fields", FlowEditorController, :fields_post

    get "/labels", FlowEditorController, :labels
    post "/labels", FlowEditorController, :labels_post

    get "/channels", FlowEditorController, :channels

    get "/classifiers", FlowEditorController, :classifiers

    get "/ticketers", FlowEditorController, :ticketers

    get "/resthooks", FlowEditorController, :resthooks

    get "/templates", FlowEditorController, :templates

    get "/languages", FlowEditorController, :languages

    get "/environment", FlowEditorController, :environment

    get "/recipients", FlowEditorController, :recipients

    get "/completion", FlowEditorController, :completion

    get "/activity", FlowEditorController, :activity

    get "/functions", FlowEditorController, :functions

    get "/flows/*vars", FlowEditorController, :flows

    get "/revisions/*vars", FlowEditorController, :revisions

    post "/revisions/*vars", FlowEditorController, :save_revisions

    get "/validate-media", FlowEditorController, :validate_media
  end

  scope "/webhook", GlificWeb.Flows do
    post "/stir/survey", WebhookController, :stir_survey
  end

  # implement basic authentication for live dashboard and oban pro
  defp auth(conn, _opts) do
    username = Application.fetch_env!(:glific, :auth_username)
    password = Application.fetch_env!(:glific, :auth_password)
    Plug.BasicAuth.basic_auth(conn, username: username, password: password)
  end

  # defp debug_response(conn, _) do
  #  Plug.Conn.register_before_send(conn, fn conn ->
  #    conn.resp_body |> IO.puts()
  #    conn
  #  end)
  # end
end
