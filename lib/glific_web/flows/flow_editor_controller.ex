defmodule GlificWeb.Flows.FlowEditorController do
  @moduledoc """
  The Flow Editor Controller
  """

  use GlificWeb, :controller

  plug(:set_appsignal_namespace)

  alias Glific.{
    Contacts,
    Dialogflow,
    Flows,
    Flows.ContactField,
    Flows.Flow,
    Flows.FlowCount,
    Flows.FlowLabel,
    GCS.GcsWorker,
    Groups,
    Partners,
    Repo,
    Settings,
    Sheets,
    Templates.InteractiveTemplate,
    Templates.InteractiveTemplates,
    Users.User
  }

  defp set_appsignal_namespace(conn, _params) do
    # Configures all actions in this controller to report
    Glific.Appsignal.set_namespace("flow_editor_controller")
    conn
  end

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
      Groups.list_groups(
        %{filter: %{organization_id: conn.assigns[:organization_id]}},
        true
      )
      |> Enum.reduce([], fn group, acc ->
        [%{uuid: "#{group.id}", name: group.label, type: "group"} | acc]
      end)

    conn
    |> json(%{results: group_list})
  end

  @doc false
  @spec groups_post(Plug.Conn.t(), map) :: Plug.Conn.t()
  def groups_post(conn, _params) do
    conn
    |> json(%{
      uuid: 0,
      query: nil,
      status: "not-ready",
      count: 0,
      name: "ALERT: PLEASE CREATE NEW GROUP FROM THE ORGANIZATION SETTINGS"
    })
  end

  @doc false
  @spec users(Plug.Conn.t(), map) :: Plug.Conn.t()
  def users(conn, _params) do
    user_list =
      Glific.Users.list_users(%{filter: %{organization_id: conn.assigns[:organization_id]}})
      |> Enum.reduce([], fn user, acc ->
        [%{uuid: "#{user.id}", name: user.name, type: "user"} | acc]
      end)

    conn
    |> json(%{results: user_list})
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
    ContactField.create_contact_field(%{
      name: params["label"],
      shortcode: String.downcase(params["label"]) |> String.replace(" ", "_"),
      organization_id: conn.assigns[:organization_id]
    })
    |> case do
      {:ok, contact_field} ->
        conn
        |> json(%{
          key: contact_field.shortcode,
          name: contact_field.name,
          label: contact_field.name,
          value_type: contact_field.value_type
        })

      {:error, _} ->
        conn
        |> put_status(400)
        |> json(%{
          error: %{status: 400, message: "Cannot create new field with label #{params["label"]}"}
        })
    end
  end

  @doc """
    Get all the tags so that user can apply them on incoming message.
    We are not supporting this for now. To enable It should return a list of map having
    uuid and name as keys
    [%{uuid: tag.uuid, name: tag.label}]
  """
  @spec labels(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def labels(conn, _params) do
    flow_list = FlowLabel.get_all_flowlabel(conn.assigns[:organization_id])

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
  A list of all the NLP classifiers. For Glific it's just Dialogflow
  We are not supporting them for now. We will come back to this in near future
  """
  @spec classifiers(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def classifiers(conn, _params) do
    organization_id = conn.assigns[:organization_id]

    classifiers = %{
      results: [
        %{
          uuid: "dialogflow_uuid",
          name: "Dialogflow",
          type: "dialogflow",
          intents: Dialogflow.Intent.get_intent_name_list(organization_id)
        }
      ]
    }

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

  @doc """
  A list of all the interactive templates in format that is understood by flow editor
  """
  @spec interactive_templates(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def interactive_templates(conn, _params) do
    results =
      InteractiveTemplates.list_interactives(%{
        filter: %{organization_id: conn.assigns[:organization_id]}
      })
      |> Enum.reduce([], fn interactive, acc ->
        [
          %{
            id: interactive.id,
            name: interactive.label,
            type: interactive.type,
            interactive_content: interactive.interactive_content,
            created_on: interactive.inserted_at,
            modified_on: interactive.updated_at
          }
          | acc
        ]
      end)

    json(conn, %{results: results})
  end

  @doc """
  Fetching single interactive template and returning in format that is understood by flow editor
  or
  Return error Interactive message not found
  """
  @spec interactive_template(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def interactive_template(conn, params) do
    [id] = params["vars"]
    {:ok, id} = Glific.parse_maybe_integer(id)

    case Repo.fetch_by(InteractiveTemplate, %{id: id}) do
      {:ok, interactive_template} ->
        %{
          id: interactive_template.id,
          name: interactive_template.label,
          type: interactive_template.type,
          interactive_content: interactive_template.interactive_content,
          created_on: interactive_template.inserted_at,
          modified_on: interactive_template.updated_at,
          translations: get_interactive_translations(interactive_template.translations)
        }
        |> then(&json(conn, &1))

      {:error, _} ->
        json(conn, %{error: "Interactive message not found"})
    end
  end

  @spec get_interactive_translations(map) :: map()
  defp get_interactive_translations(interactive_translations) do
    language_map = Settings.get_language_id_local_map()

    interactive_translations
    |> Enum.map(fn {language_id, value} -> %{language_map[language_id] => value} end)
    |> Enum.reduce(%{}, fn translation, acc -> Map.merge(acc, translation) end)
  end

  @doc false
  @spec templates(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def templates(conn, _params) do
    results =
      Glific.Templates.list_session_templates(%{
        filter: %{organization_id: conn.assigns[:organization_id], status: "APPROVED"}
      })
      |> Enum.reduce([], fn template, acc ->
        template = Glific.Repo.preload(template, :language)
        language = template.language

        [
          %{
            uuid: template.uuid,
            name: template.label,
            type: template.type,
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
    language_map = Settings.get_language_id_local_map()

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
      |> Enum.reduce([], fn c, acc ->
        [%{id: "#{c.id}", name: c.name, type: "contact", extra: c.id} | acc]
      end)

    groups =
      Groups.list_groups(%{})
      |> Enum.reduce([], fn g, acc ->
        [%{id: "#{g.id}", name: g.label, type: "group", extra: g.id} | acc]
      end)

    json(conn, %{results: recipients ++ groups})
  end

  @doc """
  instead of reading a file we can call it directly from Assets.
  We will come back on that when we have more clarity of the use cases
  """
  @spec completion(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def completion(conn, _params) do
    completion =
      File.read!(Path.join(:code.priv_dir(:glific), "data/flows/completion.json"))
      |> Jason.decode!()

    functions =
      File.read!(Path.join(:code.priv_dir(:glific), "data/flows/functions.json"))
      |> Jason.decode!()

    results = %{
      context: completion,
      functions: functions
    }

    json(conn, results)
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
            filter: %{
              organization_id: conn.assigns[:organization_id],
              status: "published",
              is_active: true
            }
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
                 Repo.fetch_by(Flow, %{
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
      [flow_uuid, revision_id] -> json(conn, Flows.get_flow_revision(flow_uuid, revision_id))
    end
  end

  @doc """
    Save a revision for a flow and get the revision id
  """
  @spec save_revisions(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def save_revisions(conn, params) do
    user = conn.assigns[:current_user]
    revision = Flows.create_flow_revision(params, user.id)
    json(conn, %{revision: revision.id})
  end

  @doc """
    Validate media to send as attachment
  """
  @spec validate_media(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def validate_media(conn, params) do
    json(conn, Glific.Messages.validate_media(params["url"], params["type"]))
  end

  @doc false
  @spec attachments_enabled(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def attachments_enabled(conn, _) do
    organization_id = conn.assigns[:organization_id]
    json(conn, %{is_enabled: Partners.attachments_enabled?(organization_id)})
  end

  @doc false
  @spec flow_attachment(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def flow_attachment(conn, %{"media" => media, "extension" => extension} = _params) do
    organization_id = conn.assigns[:organization_id]

    remote_name =
      conn.assigns[:current_user]
      |> remote_name(extension)

    res =
      GcsWorker.upload_media(media.path, remote_name, organization_id)
      |> case do
        {:ok, media} -> %{url: media.url, type: media.type, error: nil}
        {:error, error} -> %{url: nil, error: error}
      end

    json(conn, res)
  end

  @doc false
  @spec sheets(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def sheets(conn, _params) do
    results =
      Sheets.list_sheets(%{
        filter: %{organization_id: conn.assigns[:organization_id], is_active: true}
      })
      |> Enum.reduce([], fn sheet, acc ->
        [
          %{
            id: sheet.id,
            name: sheet.label,
            url: sheet.url,
            type: sheet.type
          }
          | acc
        ]
      end)

    json(conn, %{results: results})
  end

  @doc false
  @spec recents(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def recents(conn, params) do
    [exit_uuid, destination_uuid, flow_uuid] = params["vars"]

    {:ok, flow_count} =
      Repo.fetch_by(FlowCount, %{
        uuid: exit_uuid,
        destination_uuid: destination_uuid,
        flow_uuid: flow_uuid,
        organization_id: conn.assigns[:organization_id]
      })

    results =
      Enum.reduce(flow_count.recent_messages, [], fn recent_message, acc ->
        [
          %{
            contact: recent_message["contact"],
            operand: recent_message["message"],
            time: recent_message["date"]
          }
          | acc
        ]
      end)

    json(conn, results)
  end

  @doc false
  @spec generate_uuid() :: String.t()
  defp generate_uuid do
    Ecto.UUID.generate()
  end

  @spec remote_name(User.t() | nil, String.t(), Ecto.UUID.t()) :: String.t()
  defp remote_name(user, extension, uuid \\ Ecto.UUID.generate()) do
    {year, week} = Timex.iso_week(Timex.now())
    "outbound/#{year}-#{week}/#{user.name}/#{uuid}.#{extension}"
  end
end
