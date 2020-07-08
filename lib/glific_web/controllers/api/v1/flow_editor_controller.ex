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
    }

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
    }

    json(conn, classifiers)
  end

  def ticketers(conn, params) do
    ticketers = %{
      results: [
        %{
          uuid: generate_uuid(),
          name: "Email",
          type: "mailgun",
          created_on: "2019-10-15T20:07:58.529130Z"
        }
      ]
    }

    json(conn, ticketers)
  end

  def resthooks(conn, params) do
    resthooks = %{
      results: [
        %{resthook: "my-first-zap", subscribers: []},
        %{resthook: "my-other-zap", subscribers: []}
      ]
    }

    json(conn, resthooks)
  end

  def templates(conn, params) do
    templates = %{
      results: [
        %{
          uuid: generate_uuid(),
          name: "sample_template",
          created_on: "2019-04-02T22:14:31.549213Z",
          modified_on: "2019-04-02T22:14:31.569739Z",
          translations: [
            %{
              language: "eng",
              content: "Hi {{1}}, are you still experiencing problems with {{2}}?",
              variable_count: 2,
              status: "approved",
              channel: %{
                uuid: "0f661e8b-ea9d-4bd3-9953-d368340acf91",
                name: "WhatsApp"
              }
            },
            %{
              language: "fra",
              content: "Bonjour {{1}}, a tu des problems avec {{2}}?",
              variable_count: 2,
              status: "pending",
              channel: %{
                uuid: "0f661e8b-ea9d-4bd3-9953-d368340acf91",
                name: "WhatsApp"
              }
            }
          ]
        }
      ]
    }

    json(conn, templates)
  end


  def languages(conn, params) do
    languages = %{
      results: [
        %{
            iso: "eng",
            name: "English"
          },
        %{
            iso: "Hi",
            name: "Hindi"
          }
      ]
    }

    json(conn, languages)
  end


  def environment(conn, params) do
    environment = %{
      date_format: "YYYY-MM-DD",
      time_format: "hh:mm",
      timezone: "Africa/Kigali",
      languages: ["eng", "spa", "fra"]
    }

    json(conn, environment)
  end

  def recipients(conn, params) do
    recipients = %{
      results: [
         %{
            name: "Cat Fanciers",
            id: "eae05fb1-3021-4df2-a443-db8356b953fa",
            type: "group",
            extra: 212
          },
         %{
            name: "Anne",
            id: "673fa0f6-dffd-4e7d-bcc1-e5709374354f",
            type: "contact"
          }
      ]
    }

    json(conn, recipients)
  end

  def completion(conn, params) do
    json(conn, %{})
  end






  defp generate_uuid() do
    Faker.UUID.v4()
  end
end
