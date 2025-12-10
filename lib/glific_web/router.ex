defmodule GlificWeb.Router do
  @moduledoc """
  a default gateway for all the external requests
  """
  use GlificWeb, :router

  import GlificWeb.UserAuth
  @dialyzer {:nowarn_function, __checks__: 0}
  use Appsignal.Plug

  use GlificWeb.InjectOban

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {GlificWeb.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(Pow.Plug.Session, otp_app: :glific)
  end

  pipeline :phx_browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {GlificWeb.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:fetch_current_user)
  end

  pipeline :mounted_apps do
    plug(:accepts, ["html"])
    plug(:put_secure_browser_headers)
  end

  scope path: "/feature-flags" do
    pipe_through([:mounted_apps, :auth])
    forward("/", FunWithFlags.UI.Router, namespace: "feature-flags")
  end

  pipeline :api do
    plug(:accepts, ["json"])
    plug(GlificWeb.APIAuthPlug, otp_app: :glific)
    plug(GlificWeb.RateLimitPlug)
    # plug :debug_response
  end

  pipeline :api_protected do
    plug(Pow.Plug.RequireAuthenticated, error_handler: GlificWeb.APIAuthErrorHandler)
    plug(GlificWeb.ContextPlug)
  end

  # Glific Default Route
  scope "/", GlificWeb do
    pipe_through(:browser)

    get("/", LandingPageController, :index)
  end

  # Glific Authentication routes
  scope "/api/v1", GlificWeb.API.V1, as: :api_v1 do
    pipe_through(:api)

    resources("/registration", RegistrationController, singleton: true, only: [:create])
    post("/registration/send-otp", RegistrationController, :send_otp)
    post("/registration/reset-password", RegistrationController, :reset_password)
    resources("/session", SessionController, singleton: true, only: [:create, :delete])
    post("/session/renew", SessionController, :renew)
    post("/session/name", SessionController, :name)
    post("/session/tracker", SessionController, :tracker)
    post("/onboard/setup", OnboardController, :setup)
    post("/onboard/update-registration-details", OnboardController, :update_registration)
    post("/onboard/reachout", OnboardController, :reachout)
    post "/askme", AskmeController, :ask
    post("/trial/allocate-account", TrialAccountController, :trial)
    post("/trial/create-trial-user", TrialUsersController, :create_trial_user)
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
    pipe_through([:browser, :auth])
    live_dashboard("/dashboard", metrics: GlificWeb.Telemetry, ecto_repos: [Glific.Repo])
  end

  scope "/", GlificWeb do
    pipe_through([:phx_browser, :require_authenticated_user])

    live_session(:authenticated, on_mount: {GlificWeb.UserAuth, :ensure_authenticated}) do
      # live("/stats", StatsLive)
      ## add all the authenticated live views here.
    end
  end

  # Custom stack for Absinthe
  scope "/" do
    pipe_through([:api, :api_protected])

    forward("/api", Absinthe.Plug, schema: GlificWeb.Schema)
  end

  # BSP webhooks
  scope "/", GlificWeb do
    forward("/gupshup", Providers.Gupshup.Plugs.Shunt)
    forward("/gupshup-enterprise", Providers.Gupshup.Enterprise.Plugs.Shunt)
    forward("/maytapi", Providers.Maytapi.Plugs.Shunt)
  end

  # """
  # Third party webhook except BSPs. Ideally we should have merge the BSPs also in this scope.
  # But since the BSP is a primary webhooks for this application We kept it separated.
  # """

  scope "/webhook", GlificWeb do
    post("/stripe", StripeController, :stripe_webhook)
    post("/flow_resume", Flows.FlowResumeController, :flow_resume_with_results)
    get("/exotel/optin", ExotelController, :optin)
  end

  # """
  # All the flow editor routes which is used while designing the flow.
  # """

  scope "/flow-editor", GlificWeb.Flows do
    pipe_through([:api, :api_protected])

    get("/groups", FlowEditorController, :groups)
    post("/groups", FlowEditorController, :groups_post)

    get("/users", FlowEditorController, :users)

    get("/labels", FlowEditorController, :labels)
    post("/labels", FlowEditorController, :labels_post)

    get("/channels", FlowEditorController, :channels)

    get("/classifiers", FlowEditorController, :classifiers)

    get("/ticketers", FlowEditorController, :ticketers)

    get("/resthooks", FlowEditorController, :resthooks)

    get("/templates", FlowEditorController, :templates)

    get("/interactive-templates", FlowEditorController, :interactive_templates)

    get("/interactive-templates/*vars", FlowEditorController, :interactive_template)

    get("/languages", FlowEditorController, :languages)

    get("/environment", FlowEditorController, :environment)

    get("/recipients", FlowEditorController, :recipients)

    get("/activity", FlowEditorController, :activity)

    get("/flows/*vars", FlowEditorController, :flows)

    get("/revisions/*vars", FlowEditorController, :revisions)

    get("/recents/*vars", FlowEditorController, :recents)

    post("/revisions/*vars", FlowEditorController, :save_revisions)

    get("/globals", FlowEditorController, :globals)

    get("/fields", FlowEditorController, :fields)

    post("/fields", FlowEditorController, :fields_post)

    get("/completion", FlowEditorController, :completion)

    get("/validate-media", FlowEditorController, :validate_media)

    get("/attachments-enabled", FlowEditorController, :attachments_enabled)

    post("/flow-attachment", FlowEditorController, :flow_attachment)

    get("/sheets", FlowEditorController, :sheets)
  end

  if Mix.env() in [:dev, :test] do
    scope "/" do
      pipe_through([:api, :api_protected])

      forward(
        "/graphiql",
        Absinthe.Plug.GraphiQL,
        schema: GlificWeb.Schema,
        interface: :playground
      )
    end

    scope "/dev" do
      pipe_through [:browser]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  @doc """
  implement basic authentication for live dashboard and oban pro
  """
  @spec auth(any(), any()) :: any()
  def auth(conn, _opts) do
    username = Application.fetch_env!(:glific, :auth_username)
    password = Application.fetch_env!(:glific, :auth_password)
    Plug.BasicAuth.basic_auth(conn, username: username, password: password)
  end

  ## Authentication routes

  scope "/", GlificWeb do
    pipe_through([:phx_browser, :redirect_if_user_is_authenticated])
    get("/users/log_in", UserSessionController, :new)
    post("/users/log_in", UserSessionController, :create)
  end

  scope "/", GlificWeb do
    pipe_through([:phx_browser])
    delete("/users/log_out", UserSessionController, :delete)
  end
end
