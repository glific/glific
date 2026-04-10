defmodule Glific.DifyTableQuery do
  @moduledoc """
  Dynamic table query engine for Dify callbacks.
  Provides a safe, whitelisted interface for querying Glific tables
  with caller-specified filters, fields, ordering, and limits.
  """

  require Logger

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactHistory,
    Flows.Flow,
    Flows.FlowContext,
    Flows.FlowResult,
    Flows.FlowRevision,
    Groups.ContactGroup,
    Groups.Group,
    Messages.Message,
    Notifications.Notification,
    Repo,
    Tags.Tag,
    Templates.SessionTemplate,
    Tickets.Ticket,
    Triggers.Trigger,
    WAGroup.WAMessage
  }

  @max_limit 50

  # Table name → Ecto schema mapping
  @table_schemas %{
    "contacts" => Contact,
    "messages" => Message,
    "flows" => Flow,
    "flow_contexts" => FlowContext,
    "flow_results" => FlowResult,
    "flow_revisions" => FlowRevision,
    "notifications" => Notification,
    "contact_histories" => ContactHistory,
    "triggers" => Trigger,
    "groups" => Group,
    "contacts_groups" => ContactGroup,
    "tags" => Tag,
    "session_templates" => SessionTemplate,
    "tickets" => Ticket,
    "wa_messages" => WAMessage
  }

  # Allowed fields per table (only these can be selected/filtered)
  @allowed_fields %{
    "contacts" => ~w(id name phone status bsp_status optin_status optin_time optin_method
                     optout_time last_message_at last_communication_at fields settings
                     inserted_at updated_at)a,
    "messages" => ~w(id body type flow status bsp_status errors send_at sent_at
                     message_number flow_id sender_id receiver_id contact_id
                     inserted_at updated_at)a,
    "flows" => ~w(id name uuid keywords is_active is_pinned is_background
                  respond_other ignore_keywords version_number description
                  inserted_at updated_at)a,
    "flow_contexts" => ~w(id flow_id flow_uuid contact_id status node_uuid parent_id
                          results is_killed is_background_flow is_await_result
                          wakeup_at completed_at reason inserted_at updated_at)a,
    "flow_results" => ~w(id contact_id flow_id flow_uuid flow_version results
                         inserted_at updated_at)a,
    "flow_revisions" => ~w(id flow_id revision_number status version
                           inserted_at updated_at)a,
    "notifications" => ~w(id category message severity entity is_read
                          inserted_at updated_at)a,
    "contact_histories" => ~w(id contact_id event_type event_label event_meta
                              event_datetime inserted_at updated_at)a,
    "triggers" => ~w(id name flow_id start_at end_date is_active is_repeating
                     frequency days inserted_at updated_at)a,
    "groups" => ~w(id label description is_restricted group_type
                   inserted_at updated_at)a,
    "contacts_groups" => ~w(id contact_id group_id inserted_at updated_at)a,
    "tags" => ~w(id label shortcode description is_active color_code keywords
                 inserted_at updated_at)a,
    "session_templates" => ~w(id label body type shortcode status category
                              is_hsm is_active number_parameters uuid
                              inserted_at updated_at)a,
    "tickets" => ~w(id body topic status remarks contact_id user_id flow_id
                    message_number inserted_at updated_at)a,
    "wa_messages" => ~w(id body type flow status bsp_status contact_id
                        wa_group_id is_dm inserted_at)a
  }

  @doc """
  Queries multiple tables based on the request spec.
  Returns `{:ok, %{"table_name" => [rows, ...]}}`.
  Never raises — unknown tables or bad filters produce empty results.
  """
  @spec query_tables(non_neg_integer(), map(), String.t()) :: {:ok, map()}
  def query_tables(organization_id, tables, time_range) when is_map(tables) do
    time_threshold = parse_time_range(time_range)

    results =
      tables
      |> Enum.map(fn {table_name, spec} ->
        Task.async(fn ->
          Repo.put_organization_id(organization_id)
          rows = query_single_table(organization_id, table_name, spec, time_threshold)
          {table_name, rows}
        end)
      end)
      |> Task.await_many(15_000)
      |> Map.new()

    {:ok, results}
  end

  def query_tables(_organization_id, _tables, _time_range), do: {:ok, %{}}

  defp query_single_table(organization_id, table_name, spec, time_threshold) do
    schema = Map.get(@table_schemas, table_name)
    allowed = Map.get(@allowed_fields, table_name)

    if is_nil(schema) or is_nil(allowed) do
      Logger.warning("DifyTableQuery: unknown table #{table_name}, skipping")
      []
    else
      do_query(organization_id, schema, allowed, table_name, spec, time_threshold)
    end
  rescue
    e ->
      Logger.error(
        "DifyTableQuery: error querying #{table_name}: #{Exception.message(e)}"
      )

      []
  end

  defp do_query(organization_id, schema, allowed, table_name, spec, time_threshold) do
    filters = normalize_filters(Map.get(spec, "filters", %{}))
    requested_fields = parse_fields(Map.get(spec, "fields", []), allowed)
    limit = parse_limit(Map.get(spec, "limit", @max_limit))
    order = parse_order(Map.get(spec, "order", "inserted_at DESC"), allowed)

    # Select fields — always include :id, and add :organization_id for the query
    select_fields = Enum.uniq([:id | requested_fields])

    query =
      schema
      |> apply_org_filter(organization_id)
      |> apply_filters(filters, allowed, table_name, organization_id)
      |> apply_time_range(time_threshold, allowed)
      |> apply_order(order)
      |> limit(^limit)
      |> select_fields(select_fields)

    Repo.all(query, skip_organization_id: true)
    |> Enum.map(&row_to_map(&1, select_fields))
  end

  # --- Org filter ---

  defp apply_org_filter(queryable, organization_id) do
    from(q in queryable, where: q.organization_id == ^organization_id)
  end

  # --- Filters ---

  defp normalize_filters(filters) when is_map(filters) do
    Map.new(filters, fn {k, v} -> {safe_to_existing_atom(k), v} end)
  end

  defp normalize_filters(_), do: %{}

  defp apply_filters(query, filters, allowed, table_name, organization_id) do
    Enum.reduce(filters, query, fn {field, value}, acc ->
      cond do
        # flow_uuid filter on tables that use flow_id
        field == :flow_uuid and table_name in ~w(flow_revisions triggers) ->
          apply_flow_uuid_filter(acc, value, organization_id)

        # entity JSONB filters on notifications
        is_binary(field) and String.starts_with?(to_string(field), "entity_") ->
          json_key = field |> to_string() |> String.replace_prefix("entity_", "")
          apply_jsonb_filter(acc, :entity, json_key, value)

        # Normal field filter — must be in whitelist
        field in allowed ->
          apply_value_filter(acc, field, value)

        true ->
          acc
      end
    end)
  end

  defp apply_value_filter(query, field, values) when is_list(values) do
    from(q in query, where: field(q, ^field) in ^values)
  end

  defp apply_value_filter(query, field, value) do
    from(q in query, where: field(q, ^field) == ^value)
  end

  defp apply_flow_uuid_filter(query, flow_uuid, organization_id) do
    case Repo.one(
           from(f in Flow,
             where: f.uuid == ^flow_uuid and f.organization_id == ^organization_id,
             select: f.id
           ),
           skip_organization_id: true
         ) do
      nil -> from(q in query, where: false)
      flow_id -> from(q in query, where: q.flow_id == ^flow_id)
    end
  end

  defp apply_jsonb_filter(query, column, json_key, value) do
    from(q in query,
      where: fragment("?->>? = ?", field(q, ^column), ^json_key, ^to_string(value))
    )
  end

  # --- Time range ---

  defp apply_time_range(query, nil, _allowed), do: query

  defp apply_time_range(query, time_threshold, allowed) do
    if :inserted_at in allowed do
      from(q in query, where: q.inserted_at >= ^time_threshold)
    else
      query
    end
  end

  # --- Ordering ---

  defp parse_order(order_str, allowed) when is_binary(order_str) do
    case String.split(order_str, " ", parts: 2) do
      [field_str, dir_str] ->
        field = safe_to_existing_atom(field_str)
        dir = if String.downcase(dir_str) == "asc", do: :asc, else: :desc

        if field in allowed, do: [{dir, field}], else: [{:desc, :inserted_at}]

      [field_str] ->
        field = safe_to_existing_atom(field_str)
        if field in allowed, do: [{:desc, field}], else: [{:desc, :inserted_at}]

      _ ->
        [{:desc, :inserted_at}]
    end
  end

  defp parse_order(_, _), do: [{:desc, :inserted_at}]

  defp apply_order(query, order_list) do
    Enum.reduce(order_list, query, fn {dir, field}, acc ->
      from(q in acc, order_by: [{^dir, field(q, ^field)}])
    end)
  end

  # --- Field selection ---

  defp parse_fields(fields, allowed) when is_list(fields) do
    fields
    |> Enum.map(&safe_to_existing_atom/1)
    |> Enum.filter(&(&1 in allowed))
    |> case do
      [] -> allowed
      selected -> selected
    end
  end

  defp parse_fields(_, allowed), do: allowed

  defp parse_limit(limit) when is_integer(limit) and limit > 0, do: min(limit, @max_limit)
  defp parse_limit(_), do: @max_limit

  defp select_fields(query, fields) do
    from(q in query, select: map(q, ^fields))
  end

  defp row_to_map(row, _fields) when is_map(row), do: row

  # --- Helpers ---

  defp safe_to_existing_atom(value) when is_atom(value), do: value

  defp safe_to_existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp safe_to_existing_atom(value), do: value

  defp parse_time_range("1h"), do: DateTime.add(DateTime.utc_now(), -1, :hour)
  defp parse_time_range("3d"), do: DateTime.add(DateTime.utc_now(), -3, :day)
  defp parse_time_range("7d"), do: DateTime.add(DateTime.utc_now(), -7, :day)
  defp parse_time_range("30d"), do: DateTime.add(DateTime.utc_now(), -30, :day)
  defp parse_time_range("24h"), do: DateTime.add(DateTime.utc_now(), -24, :hour)
  defp parse_time_range(_), do: nil
end
