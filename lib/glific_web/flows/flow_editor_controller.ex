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
    fileds = [
      %{key: "name", name: "Name", value_type: "text"},
      %{key: "age_group", name: "Age Group", value_type: "text"},
      %{key: "gender", name: "Gender", value_type: "text"},
      %{key: "dob", name: "Date of Birth", value_type: "text"},
      %{key: "settings", name: "Settings", value_type: "text"}
    ]

    json(conn, %{results: fileds})
  end

  @doc """
    Add Contact fields into the database. The response should be a map with 3 keys
    % { Key: Field name, name: Field display name value_type: type of the value}

    We are not supporting this for now. We will add that in future
  """

  @spec fields_post(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def fields_post(conn, _params) do
    conn
    |> json(%{})
  end

  @doc """
    Get all the tags so that user can apply them on incoming message.
    We are not supporting this for now. To enable It should return a list of map having
    uuid and name as keys
    [%{uuid: tag.uuid, name: tag.label}]

    We are not supporting them for now. We will come back to this in near future

  """
  @spec labels(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def labels(conn, _params) do
    json(conn, %{results: []})
  end

  @doc """
    Store a lable (new tag) in the system. The return response should be a map of 3 keys.
    [%{uuid: tag.uuid, name: params["name"], count}]

    We are not supporting them for now. We will come back to this in near future

  """
  @spec labels_post(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def labels_post(conn, _params) do
    json(conn, %{})
  end

  @doc """
    A list of all the communication channels. For Glific it's just WhatsApp.
    We are not supporting them for now. We will come back to this in near future
  """
  @spec channels(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def channels(conn, _params) do
    channels = %{
      results: [
        %{
          uuid: generate_uuid(),
          name: "WhatsApp",
          address: "",
          schemes: ["whatsapp"],
          roles: ["send", "receive"]
        }
      ]
    }

    json(conn, channels)
  end

  @doc """
    A list of all the communication channels. For Glific it's just WhatsApp.
    We are not supporting them for now. We will come back to this in near future
  """
  @spec classifiers(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def classifiers(conn, _params) do
    classifiers = %{results: []}
    json(conn, classifiers)
  end

  @doc """
    We are not sure how to use this but this endpoint is required for flow editor.
    Will come back to this in future.
  """
  @spec ticketers(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def ticketers(conn, _params) do
    ticketers = %{results: []}
    json(conn, ticketers)
  end

  @doc """
    We are not using this for now but this is required for flow editor config.
  """

  @spec resthooks(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def resthooks(conn, _params) do
    resthooks = %{results: []}
    json(conn, resthooks)
  end

  @doc false
  @spec templates(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def templates(conn, _params) do
    results =
      Glific.Templates.list_session_templates()
      |> Enum.reduce([], fn template, acc ->
        template = Glific.Repo.preload(template, :language)
        language = template.language

        [
          %{
            uuid: template.uuid,
            name: template.label,
            created_on: template.inserted_at,
            modified_on: template.updated_at,
            translations: [
              %{
                language: language.locale,
                content: template.body,
                variable_count: template.number_parameters,
                status: "approved",
                channel: %{uuid: "", name: "WhatsApp"}
              }
            ]
          }
          | acc
        ]
      end)

    json(conn, %{results: results})
  end

  @doc false
  @spec languages(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def languages(conn, _params) do
    results =
      Glific.Settings.list_languages()
      |> Enum.reduce([], fn language, acc ->
        [%{iso: language.locale, name: language.label} | acc]
      end)

    json(conn, %{results: results})
  end

  @doc false
  @spec environment(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def environment(conn, _params) do
    environment = %{}
    json(conn, environment)
  end

  @doc false
  @spec recipients(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def recipients(conn, _params) do
    recipients = %{results: []}
    json(conn, recipients)
  end

  @doc """
    instead of reading a file we can call it directly from Assests.
    We will come back on that when we have more clearity of the use cases
  """
  @spec completion(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def completion(conn, _params) do
    completion =
      File.read!("assets/flows/completion.json")
      |> Jason.decode!()

    json(conn, completion)
  end

  @doc """
    This is used to checking if the connection between frontend and backend is established or not.
  """
  @spec activity(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def activity(conn, _params) do
    activity = %{
      nodes: %{},
      segments: %{}
    }

    json(conn, activity)
  end

  @doc """
    Let's get all the flows or a latest flow revision
  """

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

  @doc """
    Get all or a specific revision for a flow
  """
  @spec revisions(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def revisions(conn, %{"vars" => vars}) do
    case vars do
      [flow_uuid] -> json(conn, Flows.get_flow_revision_list(flow_uuid))
      [flow_uuid, revison_id] -> json(conn, Flows.get_flow_revision(flow_uuid, revison_id))
    end
  end

  @doc """
    Save a revision for a flow and get the revision id
  """
  @spec save_revisions(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def save_revisions(conn, params) do
    revision = Flows.create_flow_revision(params)
    json(conn, %{revision: revision.id})
  end

  @doc """
    all the supported funcations we provide
  """
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
    Ecto.UUID.generate()
  end
end
