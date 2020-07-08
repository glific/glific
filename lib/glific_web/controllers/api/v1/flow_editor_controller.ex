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


  def channels(conn, params) do

    channels = %{
      results: [
        %{
          uuid: generate_uuid(),
          name: "WhatsApp",
          address: "+18005234545",
          schemes: ["whatsapp"],
          roles: ["send", "receive"]
        }
      ]
    };
    json(conn, channels)
  end

  def classifiers(conn, params) do
    classifiers = %{
      results: [
        %{
          uuid: generate_uuid(),
          name: "Travel Agency",
          type: "wit",
          intents: ["book flight", "rent car"],
          created_on: "2019-10-15T20:07:58.529130Z"
        }
      ]
    };
    json(conn, classifiers)
  end



  defp generate_uuid() do
    Faker.UUID.v4()
  end


end
