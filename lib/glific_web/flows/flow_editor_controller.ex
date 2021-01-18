defmodule GlificWeb.Flows.FlowEditorController do
  @moduledoc """
  The Flow Editor Controller
  """

  use GlificWeb, :controller

  alias Glific.{
    Contacts,
    Flows,
    Flows.ContactField,
    Flows.Flow,
    Flows.FlowCount,
    Flows.FlowLabel,
    Settings
  }

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
      Glific.Groups.list_groups(
        %{filter: %{organization_id: conn.assigns[:organization_id]}},
        true
      )
      |> Enum.reduce([], fn group, acc ->
        [%{uuid: "#{group.id}", name: group.label} | acc]
      end)
      |> IO.inspect()

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
      ContactField.list_contacts_fields(%{
        filter: %{organization_id: conn.assigns[:organization_id]}
      })
      |> Enum.reduce([], fn cf, acc ->
        [%{key: cf.shortcode, name: cf.name, value_type: cf.value_type, label: cf.name} | acc]
      end)

    json(conn, %{results: fields})
  end

  @doc """
  Add Contact fields into the database. The response should be a map with 3 keys
  % { Key: Field name, name: Field display name value_type: type of the value}

  We are not supporting this for now. We will add that in future
  """

  @spec fields_post(Plug.Conn.t(), map) :: Plug.Conn.t()
  def fields_post(conn, params) do
    # need to store this into DB, the value_type will default to text in this case
    # the shortcode is the name, lower cased, and camelized
    {:ok, contact_field} =
      ContactField.create_contact_field(%{
        name: params["label"],
        shortcode: String.downcase(params["label"]) |> String.replace(" ", "_"),
        organization_id: conn.assigns[:organization_id]
      })

    conn
    |> json(%{
      key: contact_field.shortcode,
      name: contact_field.name,
      label: contact_field.name,
      value_type: contact_field.value_type
    })
  end

  @doc """
    Get all the tags so that user can apply them on incoming message.
    We are not supporting this for now. To enable It should return a list of map having
    uuid and name as keys
    [%{uuid: tag.uuid, name: tag.label}]
  """
  @spec labels(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def labels(conn, _params) do
    flow_list =
      FlowLabel.get_all_flowlabel(conn.assigns[:organization_id])
      |> Enum.reduce([], fn flow, acc ->
        [%{uuid: "#{flow.uuid}", name: flow.name} | acc]
      end)

    json(conn, %{results: flow_list})
  end

  @doc """
  Store a label (new tag) in the system. The return response should be a map of 3 keys.
  [%{uuid: tag.uuid, name: params["name"], count}]

  We are not supporting them for now. We will come back to this in near future
  """
  @spec labels_post(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def labels_post(conn, params) do
    {:ok, flow_label} =
      FlowLabel.create_flow_label(%{
        name: params["name"],
        organization_id: conn.assigns[:organization_id]
      })

    json(conn, %{uuid: flow_label.uuid, name: flow_label.name, count: 0})
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
  A list of all the NLP classifiers. For Glific it's just WhatsApp.
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
            translations:
              Enum.concat(
                [
                  %{
                    language: language.locale,
                    content: template.body,
                    variable_count: template.number_parameters,
                    status: "approved",
                    channel: %{uuid: "", name: "WhatsApp"}
                  }
                ],
                get_template_translations(template.translations)
              )
          }
          | acc
        ]
      end)

    json(conn, %{results: results})
  end

  @spec get_template_translations(nil | map) :: list()
  defp get_template_translations(nil), do: []

  defp get_template_translations(template_translations) do
    language_map =
      Map.new(Settings.locale_id_map(), fn {locale, language_id} ->
        {to_string(language_id), locale}
      end)

    template_translations
    |> Enum.reduce([], fn {language_id, translation}, acc ->
      [
        %{
          content: translation["body"],
          variable_count: translation["number_parameters"],
          status: "approved",
          language: language_map[language_id],
          channel: %{uuid: "", name: "WhatsApp"}
        }
        | acc
      ]
    end)
  end

  @doc false
  @spec languages(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def languages(conn, _params) do
    results =
      Glific.Partners.organization(conn.assigns[:organization_id]).languages
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
    # we should return only staff contact ids here
    # ideally should only be able to send them an HSM template, so we need
    # this to be fixed in the frontend
    recipients =
      Contacts.list_user_contacts()
      |> Enum.reduce([], fn c, acc -> [%{id: c.id, name: c.name, type: "contact", extra: c.id} | acc] end)

      json(conn, %{results: recipients})
  end

  @doc """
  instead of reading a file we can call it directly from Assets.
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

  @spec get_recent_message(FlowCount.t()) :: list()
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
          Flows.list_flows(%{
            filter: %{organization_id: conn.assigns[:organization_id], status: "published"}
          })
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

  @doc """
    Validate media to send as attachment
  """
  @spec validate_media(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def validate_media(conn, params) do
    json(conn, %{is_valid: Glific.validate_media?(params["url"], params["type"])})
  end

  @doc false
  @spec generate_uuid() :: String.t()
  defp generate_uuid do
    Ecto.UUID.generate()
  end
end
