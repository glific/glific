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


  def groups(conn, data) do
     conn
    |> json(%{results: []})
  end

  def groups_post(conn, params) do
    conn
    |> json(%{
        uuid: generate_uuid(),
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

  @spec fields_post(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def fields_post(conn, params) do
    conn
    |> json(%{
        key: Slug.slugify(params["label"], separator: "_"),
        name: params["label"],
        value_type: "text"
    })
  end


  def labels(conn, data) do
     conn
    |> json(%{results: []})
  end

  def labels_post(conn, params) do
    conn
    |> json(%{
        uuid: generate_uuid(),
        name: params["name"],
        count: 0
    })
  end




  defp generate_uuid() do
    Faker.UUID.v4()
  end


end
