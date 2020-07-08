defmodule GlificWeb.API.V1.FlowEditorController do
  @moduledoc """
  The Pow User Registration Controller
  """

  use GlificWeb, :controller

  alias GlificWeb.ErrorHelpers
  alias Plug.Conn

  @doc false
  def globals(conn, data) do
     conn
    |> json(%{results: []})
  end

  def groups_post(conn, params) do
    conn
    |> json(%{
        uuid: "3aa33e3e-a824-4ad3-b24a-36053a9dee71",
        query: nil,
        status: "ready",
        count: 0,
        name: params["name"]
    })
  end


  def fields(conn, data) do
     conn
    |> json(%{results: []})
  end

  def fields_post(conn, params) do
    conn
    |> json(%{
        key: Slug.slugify(params["label"], separator: "_"),
        name: params["label"],
        value_type: "text"
    })
  end


end
