defmodule GlificWeb.Router do
  @moduledoc """
  a default gateway for all the external requests
  """
  use GlificWeb, :router
  @dialyzer {:nowarn_function, __checks__: 0}
  use Plug.ErrorHandler
  use Sentry.Plug

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {GlificWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => "default-src 'self'"}
    plug Pow.Plug.Session, otp_app: :glific
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
    post "/registration/send_otp", RegistrationController, :send_otp
    resources "/session", SessionController, singleton: true, only: [:create, :delete]
    post "/session/renew", SessionController, :renew
  end


  scope "/api/v1", GlificWeb.API.V1, as: :api_v1 do
    pipe_through :api

    get "/flow-editor/globals", FlowEditorController, :globals
    get "/flow-editor/groups", FlowEditorController, :groups
    post "/flow-editor/groups", FlowEditorController, :groups_post
    get "/flow-editor/fields", FlowEditorController, :fields
    post "/flow-editor/fields", FlowEditorController, :fields_post

    get "/flow-editor/labels", FlowEditorController, :labels
    post "/flow-editor/labels", FlowEditorController, :labels_post

    get "/flow-editor/channels", FlowEditorController, :channels
    post "/flow-editor/channels", FlowEditorController, :channels

    get "/flow-editor/classifiers", FlowEditorController, :classifiers
    post "/flow-editor/classifiers", FlowEditorController, :classifiers

    get "/flow-editor/ticketers", FlowEditorController, :ticketers
    post "/flow-editor/ticketers", FlowEditorController, :ticketers

    get "/flow-editor/resthooks", FlowEditorController, :resthooks
    post "/flow-editor/resthooks", FlowEditorController, :resthooks

    get "/flow-editor/templates", FlowEditorController, :templates
    post "/flow-editor/templates", FlowEditorController, :templates

  end



  scope "/api/v1", GlificWeb.API.V1, as: :api_v1 do
    pipe_through [:api, :api_protected]

    # Your protected API endpoints here
  end

  scope "/", GlificWeb do
    pipe_through :browser

    live "/", PageLive, :index
  end

  # Custom stack for Absinthe
  scope "/" do
    pipe_through [:api]

    forward "/api", Absinthe.Plug, schema: GlificWeb.Schema

    forward "/graphiql", Absinthe.Plug.GraphiQL,
      schema: GlificWeb.Schema,
      interface: :simple,
      socket: GlificWeb.UserSocket
  end

  # Custom stack for Absinthe
  scope "/" do
    pipe_through [:api, :api_protected]

    forward "/secure/api", Glific.Absinthe.Plug, schema: GlificWeb.Schema

    forward "/secure/graphiql", Glific.Absinthe.Plug.GraphiQL,
      schema: GlificWeb.Schema,
      interface: :simple,
      socket: GlificWeb.UserSocket
  end

  scope "/", GlificWeb do
    forward("/gupshup", Providers.Gupshup.Plugs.Shunt)
    1
  end

  # defp debug_response(conn, _) do
  #  Plug.Conn.register_before_send(conn, fn conn ->
  #    conn.resp_body |> IO.puts()
  #    conn
  #  end)
  # end
end
