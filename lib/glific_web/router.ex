defmodule GlificWeb.Router do
  @moduledoc """
  a default gateway for all the external requests
  """
  use GlificWeb, :router
  @dialyzer {:nowarn_function, __checks__: 0}
  use Plug.ErrorHandler

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {GlificWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => "default-src 'self'"}
    plug Pow.Plug.Session, otp_app: :glific
  end

  scope path: "/feature-flags" do
    # ensure that this is protected once we have authentication in place
    pipe_through :browser
    forward "/", FunWithFlags.UI.Router, namespace: "feature-flags"
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug GlificWeb.APIAuthPlug, otp_app: :glific
    # plug :debug_response
  end

  pipeline :api_protected do
    plug Pow.Plug.RequireAuthenticated, error_handler: GlificWeb.APIAuthErrorHandler
    plug GlificWeb.Context
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
    pipe_through :browser
    live "/", PageLive, :index
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

  scope "/", GlificWeb do
    forward("/gupshup", Providers.Gupshup.Plugs.Shunt)
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
  end

  # defp debug_response(conn, _) do
  #  Plug.Conn.register_before_send(conn, fn conn ->
  #    conn.resp_body |> IO.puts()
  #    conn
  #  end)
  # end
end
