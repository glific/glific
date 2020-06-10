defmodule GlificWeb.Router do
  @moduledoc """
  a defult gateway for all the external requests
  """
  use GlificWeb, :router
  @dialyzer {:nowarn_function, __checks__: 0}

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {GlificWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => "default-src 'self'"}
  end

  pipeline :api do
    plug :accepts, ["json"]
    # plug :debug_response
  end

  scope "/", GlificWeb do
    pipe_through :browser

    live "/", PageLive, :index
  end

  # Custom stack for Ansinthe
  scope "/" do
    pipe_through :api

    forward "/api", Absinthe.Plug, schema: GlificWeb.Schema

    forward "/graphiql", Absinthe.Plug.GraphiQL,
      schema: GlificWeb.Schema,
      interface: :simple,
      socket: GlificWeb.UserSocket
  end

  # defp debug_response(conn, _) do
  #  Plug.Conn.register_before_send(conn, fn conn ->
  #    conn.resp_body |> IO.puts()
  #    conn
  #  end)
  # end
end
