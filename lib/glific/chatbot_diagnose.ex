defmodule Glific.ChatbotDiagnose do
  @moduledoc """
  Core logic for the chatbot diagnostic endpoint.
  Accepts a map of table queries from a Dify chatbot, executes them
  against the database with organization scoping, and returns results.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Glific.{
    Contacts.Contact,
    Flows.Flow,
    Repo
  }

  # Map of allowed table names to their Ecto schema modules.
  @table_registry %{
    "assistant_config_versions" => Glific.Assistants.AssistantConfigVersion,
    "assistants" => Glific.Assistants.Assistant,
    "contact_histories" => Glific.Contacts.ContactHistory,
    "contacts" => Glific.Contacts.Contact,
    "contacts_fields" => Glific.Contacts.ContactsField,
    "contacts_groups" => Glific.Groups.ContactGroup,
    "contacts_tags" => Glific.Tags.ContactTag,
    "contacts_wa_groups" => Glific.Groups.ContactWAGroup,
    "flow_contexts" => Glific.Flows.FlowContext,
    "flow_counts" => Glific.Flows.FlowCount,
    "flow_labels" => Glific.Flows.FlowLabel,
    "flow_results" => Glific.Flows.FlowResult,
    "flow_revisions" => Glific.Flows.FlowRevision,
    "flow_roles" => Glific.AccessControl.FlowRole,
    "flows" => Glific.Flows.Flow,
    "group_roles" => Glific.AccessControl.GroupRole,
    "groups" => Glific.Groups.Group,
    "intents" => Glific.Dialogflow.Intent,
    "interactive_templates" => Glific.Templates.InteractiveTemplate,
    "issued_certificates" => Glific.Certificates.IssuedCertificate,
    "knowledge_base_versions" => Glific.Assistants.KnowledgeBaseVersion,
    "knowledge_bases" => Glific.Assistants.KnowledgeBase,
    "message_broadcast_contacts" => Glific.Flows.MessageBroadcastContact,
    "message_broadcasts" => Glific.Flows.MessageBroadcast,
    "messages" => Glific.Messages.Message,
    "messages_conversations" => Glific.Messages.MessageConversation,
    "messages_media" => Glific.Messages.MessageMedia,
    "messages_tags" => Glific.Tags.MessageTag,
    "notifications" => Glific.Notifications.Notification,
    "organization_data" => Glific.Partners.OrganizationData,
    "organizations" => Glific.Partners.Organization,
    "profiles" => Glific.Profiles.Profile,
    "registrations" => Glific.Registrations.Registration,
    "roles" => Glific.AccessControl.Role,
    "saved_searches" => Glific.Searches.SavedSearch,
    "session_templates" => Glific.Templates.SessionTemplate,
    "sheets" => Glific.Sheets.Sheet,
    "sheets_data" => Glific.Sheets.SheetData,
    "stats" => Glific.Stats.Stat,
    "tags" => Glific.Tags.Tag,
    "templates_tags" => Glific.Tags.TemplateTag,
    "tickets" => Glific.Tickets.Ticket,
    "translate_logs" => Glific.Flows.Translate.TranslateLog,
    "trigger_logs" => Glific.Triggers.TriggerLog,
    "trigger_roles" => Glific.AccessControl.TriggerRole,
    "triggers" => Glific.Triggers.Trigger,
    "user_jobs" => Glific.Jobs.UserJob,
    "user_roles" => Glific.AccessControl.UserRole,
    "users" => Glific.Users.User,
    "users_groups" => Glific.Groups.UserGroup,
    "wa_groups" => Glific.Groups.WAGroup,
    "wa_groups_collections" => Glific.Groups.WAGroupsCollection,
    "wa_managed_phones" => Glific.WAGroup.WAManagedPhone,
    "wa_messages" => Glific.WAGroup.WAMessage,
    "wa_polls" => Glific.WAGroup.WaPoll,
    "wa_reactions" => Glific.WAGroup.WaReaction,
    "webhook_logs" => Glific.Flows.WebhookLog,
    "whatsapp_form_revisions" => Glific.WhatsappForms.WhatsappFormRevision,
    "whatsapp_forms" => Glific.WhatsappForms.WhatsappForm,
    "whatsapp_forms_responses" => Glific.WhatsappForms.WhatsappFormResponse
  }

  # Whitelisted fields per table. Only these fields can be selected/filtered.
  @allowed_fields %{
    "assistant_config_versions" =>
      ~w(id version_number kaapi_version_number description prompt provider model status failure_reason assistant_id organization_id inserted_at updated_at)a,
    "assistants" =>
      ~w(id name description kaapi_uuid assistant_display_id clone_status active_config_version_id organization_id inserted_at updated_at)a,
    "contact_histories" =>
      ~w(id event_type event_label event_datetime event_meta contact_id profile_id organization_id inserted_at updated_at)a,
    "contacts" =>
      ~w(id name phone contact_type status bsp_status is_org_read is_org_replied is_contact_replied optin_time optin_status optin_method optin_message_id optout_time optout_method first_message_number last_message_number last_message_at last_communication_at language_id active_profile_id organization_id inserted_at updated_at)a,
    "contacts_fields" =>
      ~w(id name shortcode value_type scope organization_id inserted_at updated_at)a,
    "contacts_groups" => ~w(id contact_id group_id organization_id inserted_at updated_at)a,
    "contacts_tags" => ~w(id value contact_id tag_id organization_id)a,
    "contacts_wa_groups" =>
      ~w(id is_admin contact_id wa_group_id organization_id inserted_at updated_at)a,
    "flow_contexts" =>
      ~w(id node_uuid flow_uuid status wakeup_at completed_at is_background_flow is_await_result is_killed reason contact_id flow_id organization_id parent_id profile_id message_broadcast_id wa_group_id inserted_at updated_at)a,
    "flow_counts" =>
      ~w(id uuid flow_uuid type count destination_uuid flow_id organization_id inserted_at updated_at)a,
    "flow_labels" => ~w(id uuid name type organization_id inserted_at updated_at)a,
    "flow_results" =>
      ~w(id results contact_id flow_context_id flow_id flow_uuid flow_version organization_id profile_id inserted_at updated_at)a,
    "flow_revisions" =>
      ~w(id version revision_number status flow_id user_id organization_id inserted_at updated_at)a,
    "flow_roles" => ~w(id role_id flow_id organization_id)a,
    "flows" =>
      ~w(id name description version_number flow_type uuid keywords ignore_keywords is_active is_background is_pinned is_template respond_other respond_no_response tag_id organization_id inserted_at updated_at)a,
    "group_roles" => ~w(id role_id group_id organization_id)a,
    "groups" =>
      ~w(id label description is_restricted last_message_number group_type last_communication_at organization_id inserted_at updated_at)a,
    "intents" => ~w(id name organization_id inserted_at updated_at)a,
    "interactive_templates" =>
      ~w(id label type send_with_title tag_id language_id organization_id inserted_at updated_at)a,
    "issued_certificates" =>
      ~w(id gcs_url errors certificate_template_id contact_id organization_id inserted_at updated_at)a,
    "knowledge_base_versions" =>
      ~w(id knowledge_base_id version_number status kaapi_job_id llm_service_id organization_id inserted_at updated_at)a,
    "knowledge_bases" => ~w(id name organization_id inserted_at updated_at)a,
    "message_broadcast_contacts" =>
      ~w(id processed_at status message_broadcast_id contact_id organization_id inserted_at updated_at)a,
    "message_broadcasts" =>
      ~w(id started_at completed_at type group_id message_id flow_id user_id organization_id inserted_at updated_at)a,
    "messages" =>
      ~w(id uuid body flow_label flow type status clean_body is_hsm bsp_message_id bsp_status errors send_at sent_at message_number session_uuid sender_id receiver_id contact_id user_id group_id flow_id media_id organization_id profile_id message_broadcast_id template_id interactive_template_id inserted_at updated_at)a,
    "messages_conversations" =>
      ~w(id conversation_id deduction_type is_billable message_id organization_id inserted_at updated_at)a,
    "messages_media" =>
      ~w(id url source_url thumbnail caption gcs_url content_type flow is_template_media organization_id inserted_at updated_at)a,
    "messages_tags" => ~w(id value message_id tag_id organization_id)a,
    "notifications" =>
      ~w(id category entity message severity is_read organization_id inserted_at updated_at)a,
    "organization_data" => ~w(id key description text organization_id inserted_at updated_at)a,
    "organizations" =>
      ~w(id name shortcode email is_active is_approved status timezone session_limit inserted_at updated_at)a,
    "profiles" =>
      ~w(id name type is_active is_default language_id contact_id organization_id inserted_at updated_at)a,
    "registrations" =>
      ~w(id org_details platform_details billing_frequency has_submitted has_confirmed organization_id inserted_at updated_at)a,
    "roles" => ~w(id description is_reserved label organization_id inserted_at updated_at)a,
    "saved_searches" =>
      ~w(id label shortcode is_reserved organization_id inserted_at updated_at)a,
    "session_templates" =>
      ~w(id uuid label body type shortcode quality footer status is_hsm number_parameters category is_source is_active is_reserved has_buttons button_type bsp_id reason tag_id language_id organization_id message_media_id parent_id inserted_at updated_at)a,
    "sheets" =>
      ~w(id label url type is_active last_synced_at auto_sync sheet_data_count sync_status failure_reason organization_id inserted_at updated_at)a,
    "sheets_data" => ~w(id key last_synced_at sheet_id organization_id inserted_at updated_at)a,
    "stats" =>
      ~w(id contacts active optin optout messages inbound outbound hsm flows_started flows_completed users conversations period date hour organization_id inserted_at updated_at)a,
    "tags" =>
      ~w(id label shortcode description color_code is_active is_reserved is_value keywords language_id organization_id parent_id inserted_at updated_at)a,
    "templates_tags" => ~w(id value template_id tag_id organization_id)a,
    "tickets" =>
      ~w(id body topic status remarks message_number contact_id user_id flow_id organization_id inserted_at updated_at)a,
    "translate_logs" =>
      ~w(id text translated_text translation_engine source_language destination_language status error organization_id inserted_at updated_at)a,
    "trigger_logs" =>
      ~w(id started_at trigger_id flow_context_id organization_id inserted_at updated_at)a,
    "trigger_roles" => ~w(id role_id trigger_id organization_id)a,
    "triggers" =>
      ~w(id trigger_type start_at end_date name last_trigger_at next_trigger_at frequency days hours is_active is_repeating group_type flow_id organization_id inserted_at updated_at)a,
    "user_jobs" =>
      ~w(id status type total_tasks tasks_done all_tasks_created organization_id inserted_at updated_at)a,
    "user_roles" => ~w(id user_id role_id organization_id)a,
    "users" =>
      ~w(id name email roles is_restricted last_login_at contact_id language_id organization_id inserted_at updated_at)a,
    "users_groups" => ~w(id user_id group_id organization_id)a,
    "wa_groups" =>
      ~w(id label bsp_id is_org_read last_communication_at wa_managed_phone_id organization_id inserted_at updated_at)a,
    "wa_groups_collections" =>
      ~w(id group_id wa_group_id organization_id inserted_at updated_at)a,
    "wa_managed_phones" =>
      ~w(id label phone phone_id status product_id contact_id organization_id inserted_at updated_at)a,
    "wa_messages" =>
      ~w(id uuid type flow status body bsp_status bsp_id errors message_number send_at sent_at is_dm flow_label contact_id group_id wa_group_id media_id wa_managed_phone_id organization_id message_broadcast_id inserted_at updated_at)a,
    "wa_polls" =>
      ~w(id uuid label poll_content allow_multiple_answer organization_id inserted_at updated_at)a,
    "wa_reactions" =>
      ~w(id bsp_id reaction wa_message_id contact_id organization_id inserted_at updated_at)a,
    "webhook_logs" =>
      ~w(id url method request_headers request_json response_json status_code error flow_id contact_id wa_group_id flow_context_id organization_id inserted_at updated_at)a,
    "whatsapp_form_revisions" =>
      ~w(id revision_number whatsapp_form_id user_id organization_id inserted_at updated_at)a,
    "whatsapp_forms" =>
      ~w(id name description meta_flow_id status categories sheet_id revision_id organization_id inserted_at updated_at)a,
    "whatsapp_forms_responses" =>
      ~w(id raw_response submitted_at contact_id whatsapp_form_id organization_id inserted_at updated_at)a
  }

  @max_limit 50

  @doc """
  Execute diagnostic queries for the given tables.

  Sets the organization context in the process dictionary so the Repo
  auto-scopes all queries by organization_id.
  """
  @spec run(map(), String.t() | nil, non_neg_integer()) :: map()
  def run(tables, time_range, org_id) do
    Repo.put_organization_id(org_id)
    time_threshold = parse_time_range(time_range)

    # Pre-resolve virtual filter keys once
    virtual_resolutions = resolve_virtual_filters(tables, org_id)

    tables
    |> Enum.reduce(%{}, fn {table_name, table_opts}, acc ->
      result = query_table(table_name, table_opts, time_threshold, virtual_resolutions)
      Map.put(acc, table_name, result)
    end)
  end

  @spec query_table(String.t(), map(), DateTime.t() | nil, map()) :: list()
  defp query_table(table_name, table_opts, time_threshold, virtual_resolutions) do
    with {:ok, schema} <- get_schema(table_name),
         {:ok, fields} <- get_select_fields(table_name, table_opts) do
      filters = Map.get(table_opts, "filters", %{})
      limit = table_opts |> Map.get("limit", 20) |> min(@max_limit)
      order = Map.get(table_opts, "order")

      apply_time = Map.get(table_opts, "apply_time_range", true)

      schema
      |> build_query(
        table_name,
        filters,
        virtual_resolutions,
        time_threshold,
        apply_time,
        order,
        limit
      )
      |> select_fields(fields)
      |> Repo.all()
      |> Enum.map(&schema_to_map(&1, fields))
    else
      {:error, reason} ->
        Logger.warning("ChatbotDiagnose: skipping table #{table_name}: #{reason}")
        []
    end
  rescue
    e ->
      Logger.error("ChatbotDiagnose: error querying #{table_name}: #{Exception.message(e)}")
      []
  end

  defp get_schema(table_name) do
    case Map.get(@table_registry, table_name) do
      nil -> {:error, "unknown table"}
      schema -> {:ok, schema}
    end
  end

  defp get_select_fields(table_name, table_opts) do
    allowed = Map.get(@allowed_fields, table_name, [])

    case Map.get(table_opts, "fields") do
      nil ->
        {:ok, allowed}

      requested_fields ->
        fields =
          requested_fields
          |> Enum.map(&String.to_existing_atom/1)
          |> Enum.filter(&(&1 in allowed))

        if fields == [],
          do: {:error, "no valid fields requested"},
          else: {:ok, fields}
    end
  rescue
    ArgumentError -> {:error, "invalid field name"}
  end

  defp build_query(
         schema,
         table_name,
         filters,
         virtual_resolutions,
         time_threshold,
         apply_time,
         order,
         limit
       ) do
    query = from(q in schema)

    allowed = Map.get(@allowed_fields, table_name, [])

    query
    |> maybe_apply_time_range(time_threshold, apply_time, allowed)
    |> apply_filters(filters, allowed, virtual_resolutions)
    |> apply_order(order)
    |> limit(^limit)
  end

  defp maybe_apply_time_range(query, nil, _apply_time, _allowed), do: query
  defp maybe_apply_time_range(query, _time_threshold, false, _allowed), do: query

  defp maybe_apply_time_range(query, time_threshold, true, allowed) do
    if :inserted_at in allowed do
      where(query, [q], q.inserted_at >= ^time_threshold)
    else
      query
    end
  end

  defp apply_filters(query, filters, allowed, virtual_resolutions) do
    Enum.reduce(filters, query, fn {key, value}, acc ->
      apply_single_filter(acc, key, value, allowed, virtual_resolutions)
    end)
  end

  defp apply_single_filter(query, "flow_uuid", uuid, allowed, _vr) do
    case Map.get(%{}, :unused) do
      _ ->
        if :flow_id in allowed do
          case resolve_flow_by_uuid(uuid) do
            {:ok, flow_id} -> where(query, [q], q.flow_id == ^flow_id)
            _ -> where(query, [q], fragment("1 = 0"))
          end
        else
          # If the table has flow_uuid as a direct field, filter on it
          if :flow_uuid in allowed do
            where(query, [q], q.flow_uuid == ^uuid)
          else
            query
          end
        end
    end
  end

  defp apply_single_filter(query, "contact_phone", phone, allowed, _vr) do
    if :contact_id in allowed do
      case resolve_contact_by_phone(phone) do
        {:ok, contact_id} -> where(query, [q], q.contact_id == ^contact_id)
        _ -> where(query, [q], fragment("1 = 0"))
      end
    else
      query
    end
  end

  defp apply_single_filter(query, "contact_name", name, allowed, _vr) do
    if :contact_id in allowed do
      case resolve_contact_by_name(name) do
        {:ok, contact_id} -> where(query, [q], q.contact_id == ^contact_id)
        _ -> where(query, [q], fragment("1 = 0"))
      end
    else
      query
    end
  end

  defp apply_single_filter(query, "flow_name", name, allowed, _vr) do
    if :flow_id in allowed do
      case resolve_flow_by_name(name) do
        {:ok, flow_id} -> where(query, [q], q.flow_id == ^flow_id)
        _ -> where(query, [q], fragment("1 = 0"))
      end
    else
      query
    end
  end

  defp apply_single_filter(query, key, value, allowed, _vr) do
    atom_key =
      try do
        String.to_existing_atom(key)
      rescue
        ArgumentError -> nil
      end

    cond do
      is_nil(atom_key) ->
        query

      atom_key not in allowed ->
        query

      is_nil(value) ->
        where(query, [q], is_nil(field(q, ^atom_key)))

      is_list(value) ->
        where(query, [q], field(q, ^atom_key) in ^value)

      true ->
        where(query, [q], field(q, ^atom_key) == ^value)
    end
  end

  defp select_fields(query, fields) do
    from(q in query, select: map(q, ^fields))
  end

  defp apply_order(query, nil), do: query

  defp apply_order(query, order_string) when is_binary(order_string) do
    case parse_order(order_string) do
      {:ok, order_clause} -> order_by(query, [q], ^order_clause)
      _ -> query
    end
  end

  defp parse_order(order_string) do
    parts = String.split(order_string, " ", trim: true)

    case parts do
      [field_str, dir_str] ->
        field_atom = safe_to_existing_atom(field_str)
        dir = String.downcase(dir_str)

        if field_atom do
          case dir do
            "desc" -> {:ok, [{:desc, field_atom}]}
            "asc" -> {:ok, [{:asc, field_atom}]}
            _ -> :error
          end
        else
          :error
        end

      [field_str] ->
        field_atom = safe_to_existing_atom(field_str)
        if field_atom, do: {:ok, [{:asc, field_atom}]}, else: :error

      _ ->
        :error
    end
  end

  defp safe_to_existing_atom(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end

  defp schema_to_map(record, fields) do
    Map.take(record, fields)
  end

  # --- Virtual filter resolution ---

  defp resolve_virtual_filters(tables, _org_id) do
    # Collect all virtual filter values across tables
    all_filters =
      tables
      |> Enum.flat_map(fn {_table, opts} ->
        Map.get(opts, "filters", %{}) |> Map.to_list()
      end)

    resolutions = %{}

    resolutions =
      case Enum.find(all_filters, fn {k, _} -> k == "flow_uuid" end) do
        {"flow_uuid", uuid} ->
          case resolve_flow_by_uuid(uuid) do
            {:ok, id} -> Map.put(resolutions, {:flow_uuid, uuid}, id)
            _ -> resolutions
          end

        _ ->
          resolutions
      end

    resolutions =
      case Enum.find(all_filters, fn {k, _} -> k == "contact_phone" end) do
        {"contact_phone", phone} ->
          case resolve_contact_by_phone(phone) do
            {:ok, id} -> Map.put(resolutions, {:contact_phone, phone}, id)
            _ -> resolutions
          end

        _ ->
          resolutions
      end

    resolutions
  end

  defp resolve_flow_by_uuid(uuid) do
    case Repo.one(from(f in Flow, where: f.uuid == ^uuid, select: f.id, limit: 1)) do
      nil -> :error
      id -> {:ok, id}
    end
  end

  defp resolve_flow_by_name(name) do
    pattern = "%#{name}%"

    case Repo.one(from(f in Flow, where: ilike(f.name, ^pattern), select: f.id, limit: 1)) do
      nil -> :error
      id -> {:ok, id}
    end
  end

  defp resolve_contact_by_phone(phone) do
    case Repo.one(from(c in Contact, where: c.phone == ^phone, select: c.id, limit: 1)) do
      nil -> :error
      id -> {:ok, id}
    end
  end

  defp resolve_contact_by_name(name) do
    pattern = "%#{name}%"

    case Repo.one(from(c in Contact, where: ilike(c.name, ^pattern), select: c.id, limit: 1)) do
      nil -> :error
      id -> {:ok, id}
    end
  end

  # --- Time range parsing ---

  @spec parse_time_range(String.t() | nil) :: DateTime.t() | nil
  defp parse_time_range(nil), do: nil

  defp parse_time_range(range) when is_binary(range) do
    seconds =
      case Regex.run(~r/^(\d+)(h|d)$/, range) do
        [_, num, "h"] -> String.to_integer(num) * 3600
        [_, num, "d"] -> String.to_integer(num) * 86_400
        _ -> 86_400
      end

    DateTime.utc_now() |> DateTime.add(-seconds, :second)
  end
end
