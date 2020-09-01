defmodule GlificWeb.Flows.FlowEditorController do
  @moduledoc """
  The Flow Editor Controller
  """

  use GlificWeb, :controller

  alias Glific.Flows
  alias Glific.Flows.Flow
  alias Glific.Flows.FlowCount
  alias Glific.Flows.ContactField

  @doc false
  @spec globals(Plug.Conn.t(), map) :: Plug.Conn.t()
  def globals(conn, _params) do
    conn
    |> json(%{results: []})
  end

  @doc false
  @spec groups(Plug.Conn.t(), map) :: Plug.Conn.t()
  def groups(conn, _params) do
    group_list =
      Glific.Groups.list_groups(%{filter: %{organization_id: conn.assigns[:organization_id]}})
      |> Enum.reduce([], fn group, acc ->
        [%{uuid: "#{group.id}", name: group.label} | acc]
      end)

    conn
    |> json(%{results: group_list})
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
    fields =
      ContactField.list_contacts_fields(%{filter: %{organization_id: conn.assigns[:organization_id]}})
      |> Enum.reduce([], fn cf, acc -> [%{key: cf.shortcode, name: cf.name, value_type: cf.value_type} | acc]
      end)


    # IO.inspect("fields")
    # IO.inspect(fields)

    # fields = [
    #   %{key: "name", name: "Name", value_type: "text"},
    #   %{key: "age_group", name: "Age Group", value_type: "text"},
    #   %{key: "gender", name: "Gender", value_type: "text"},
    #   %{key: "dob", name: "Date of Birth", value_type: "text"},
    #   %{key: "settings", name: "Settings", value_type: "text"}
    # ]

    json(conn, %{results: fields})
  end

  @doc """
  Add Contact fields into the database. The response should be a map with 3 keys
  % { Key: Field name, name: Field display name value_type: type of the value}

  We are not supporting this for now. We will add that in future
  """

  @spec fields_post(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def fields_post(conn, params) do
    # need to store this into DB, the value_type will default to text in this case
    # the shortcode is the name, lower cased, and camelized
    {:ok, contact_field } =
      ContactField.create_contact_field(%{
        name: params["label"],
        shortcode: Glific.string_clean(params["label"]),
        organization_id: conn.assigns[:organization_id]
      })

    conn
    |> json(%{key: contact_field.shortcode, name: contact_field.name, value_type: contact_field.value_type})
  end

  @doc """
    Get all the tags so that user can apply them on incoming message.
    We are not supporting this for now. To enable It should return a list of map having
    uuid and name as keys
    [%{uuid: tag.uuid, name: tag.label}]
  """
  @spec labels(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def labels(conn, _params) do
    tag_list =
      Glific.Tags.list_tags(%{
        filter: %{parent: "Contacts", organization_id: conn.assigns[:organization_id]}
      })
      |> Enum.reduce([], fn tag, acc ->
        [%{uuid: "#{tag.id}", name: tag.label} | acc]
      end)

    json(conn, %{results: tag_list})
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
      Glific.Templates.list_session_templates(%{
        filter: %{organization_id: conn.assigns[:organization_id]}
      })
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
      File.read!(Path.join(:code.priv_dir(:glific), "data/flows/completion.json"))
      |> Jason.decode!()

    json(conn, completion)
  end

  @doc """
    This is used to checking if the connection between frontend and backend is established or not.
  """
  @spec activity(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def activity(conn, params) do
    {nodes, segments, recent_messages} =
      FlowCount.get_flow_count_list(params["flow"])
      |> Enum.reduce(
        {%{}, %{}, %{}},
        fn fc, acc ->
          {nodes, segments, recent_messages} = acc

          case fc.type do
            "node" ->
              {Map.put(nodes, fc.uuid, fc.count), segments, recent_messages}

            "exit" ->
              key = "#{fc.uuid}:#{fc.destination_uuid}"

              {
                nodes,
                Map.put(segments, key, fc.count),
                Map.put(recent_messages, key, get_recent_message(fc))
              }

            _ ->
              acc
          end
        end
      )

    activity = %{nodes: nodes, segments: segments, recentMessages: recent_messages}
    json(conn, activity)
  end

  defp get_recent_message(flow_count) do
    # flow editor shows only last 3 messages. We are just tacking 5 for the safe side.
    flow_count.recent_messages
    |> Enum.map(fn msg -> %{text: msg["message"], sent: msg["date"]} end)
    |> Enum.take(5)
  end

  @doc """
    Let's get all the flows or a latest flow revision
  """
  @spec flows(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def flows(conn, %{"vars" => vars}) do
    results =
      case vars do
        [] ->
          ## We need to fix this before merging this branch
          Flows.list_flows(%{filter: %{organization_id: 1}})
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
          with {:ok, flow} <-
                 Glific.Repo.fetch_by(Flow, %{
                   uuid: flow_uuid,
                   organization_id: conn.assigns[:organization_id]
                 }),
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
      File.read!(Path.join(:code.priv_dir(:glific), "data/flows/functions.json"))
      |> Jason.decode!()

    json(conn, functions)
  end

  @doc false
  @spec generate_uuid() :: String.t()
  defp generate_uuid do
    Ecto.UUID.generate()
  end
end
