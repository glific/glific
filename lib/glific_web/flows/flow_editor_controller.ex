defmodule GlificWeb.Flows.FlowEditorController do
  @moduledoc """
  The Flow Editor Controller
  """

  use GlificWeb, :controller

  alias Glific.Flows
  alias Glific.Flows.Flow

  @doc false
  @spec globals(Plug.Conn.t(), map) :: Plug.Conn.t()
  def globals(conn, _params) do
    conn
    |> json(%{results: []})
  end

  @doc false
  @spec groups(Plug.Conn.t(), map) :: Plug.Conn.t()
  def groups(conn, _params) do
    conn
    |> json(%{results: []})
  end

  @doc false
  @spec groups_post(Plug.Conn.t(), map) :: Plug.Conn.t()
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

  @doc false
  @spec fields(Plug.Conn.t(), map) :: Plug.Conn.t()
  def fields(conn, _params) do
    conn
    |> json(%{results: []})
  end

  @doc false
  @spec fields_post(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def fields_post(conn, params) do
    conn
    |> json(%{
      key: Slug.slugify(params["label"], separator: "_"),
      name: params["label"],
      value_type: "text"
    })
  end

  @doc false
  @spec labels(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def labels(conn, _params) do
    conn
    |> json(%{results: []})
  end

  @doc false
  @spec labels_post(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def labels_post(conn, params) do
    conn
    |> json(%{
      uuid: generate_uuid(),
      name: params["name"],
      count: 0
    })
  end

  @doc false
  @spec channels(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def channels(conn, _params) do
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

  @doc false
  @spec classifiers(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def classifiers(conn, _params) do
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

  @doc false
  @spec ticketers(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def ticketers(conn, _params) do
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

  @doc false
  @spec resthooks(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def resthooks(conn, _params) do
    resthooks = %{
      results: [
        %{resthook: "my-first-zap", subscribers: []},
        %{resthook: "my-other-zap", subscribers: []}
      ]
    }

    json(conn, resthooks)
  end

  @doc false
  @spec templates(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def templates(conn, _params) do
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

  @doc false
  @spec languages(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def languages(conn, _params) do
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

  @doc false
  @spec environment(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def environment(conn, _params) do
    environment = %{
      date_format: "YYYY-MM-DD",
      time_format: "hh:mm",
      timezone: "Africa/Kigali",
      languages: ["eng", "spa", "fra"]
    }

    json(conn, environment)
  end

  @doc false
  @spec recipients(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def recipients(conn, _params) do
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

  @doc false
  @spec completion(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def completion(conn, _params) do
    json(conn, %{})
  end

  @doc false
  @spec activity(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def activity(conn, _params) do
    activity = %{
      nodes: %{},
      segments: %{}
    }

    json(conn, activity)
  end

  @doc false
  @spec flows(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def flows(conn, %{"vars" => vars}) do
    results =
      case vars do
        [] ->
          Flows.list_flows()
          |> Enum.reduce([], fn flow, acc ->
            [
              %{
                uuid: flow.uuid,
                name: flow.name,
                type: flow.flow_type,
                archived: false,
                labels: [],
                expires: 10_080,
                parent_refs: []
              }
              | acc
            ]
          end)

        [flow_uuid] ->
          with {:ok, flow} <- Glific.Repo.fetch_by(Flow, %{uuid: flow_uuid}),
               do: Flow.get_latest_definition(flow.id)
      end

    json(conn, %{results: results})
  end

  @doc false
  @spec revisions(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def revisions(conn, %{"vars" => vars}) do
    case vars do
      [flow_uuid] -> json(conn, Flows.get_flow_revision_list(flow_uuid))
      [flow_uuid, revison_id] -> json(conn, Flows.get_flow_revision(flow_uuid, revison_id))
    end
  end

  @doc false
  @spec save_revisions(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def save_revisions(conn, params) do
    revision = Flows.create_flow_revision(params)
    json(conn, %{revision: revision.id})
  end

  @doc false
  @spec functions(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def functions(conn, _) do
    functions =
      File.read!("assets/flows/functions.json")
      |> Jason.decode!()

    json(conn, functions)
  end

  @doc false
  @spec generate_uuid() :: String.t()
  defp generate_uuid do
    Faker.UUID.v4()
  end
end
