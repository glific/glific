defmodule Glific.ChatbotDiagnose do
  @moduledoc """
  Context module for the chatbotDiagnose GraphQL query.
  Provides a single API call to fetch diagnostic data across multiple tables
  for AI chatbot consumption.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactHistory,
    Flows.Flow,
    Flows.FlowContext,
    Flows.FlowResult,
    Flows.FlowRevision,
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

  @default_limit 20
  @max_limit 50

  @all_sections ~w(
    CONTACT_INFO CONTACT_FIELDS CONTACT_HISTORY MESSAGES
    FLOW_INFO FLOW_REVISIONS FLOW_CONTEXTS FLOW_RESULTS
    NOTIFICATIONS TRIGGERS OBAN_JOBS GROUPS CONTACT_GROUPS
    TAGS TEMPLATES WA_MESSAGES TICKETS
  )

  @contact_sections ~w(
    CONTACT_INFO CONTACT_FIELDS CONTACT_HISTORY MESSAGES
    FLOW_CONTEXTS FLOW_RESULTS CONTACT_GROUPS TAGS WA_MESSAGES TICKETS
  )

  @flow_sections ~w(
    FLOW_INFO FLOW_REVISIONS FLOW_CONTEXTS FLOW_RESULTS TRIGGERS NOTIFICATIONS
  )

  @doc """
  Main entry point. Orchestrates which sections to fetch based on the include list
  and filters provided.
  """
  @spec diagnose(non_neg_integer(), map()) :: {:ok, map()}
  def diagnose(organization_id, args) do
    contact_filter = Map.get(args, :contact)
    flow_filter = Map.get(args, :flow)
    time_range = parse_time_range(Map.get(args, :time_range, "24h"))
    limit = min(Map.get(args, :limit, @default_limit), @max_limit)
    include = Map.get(args, :include)

    sections = resolve_sections(include, contact_filter, flow_filter)

    opts = %{
      organization_id: organization_id,
      contact_filter: contact_filter,
      flow_filter: flow_filter,
      time_range: time_range,
      limit: limit
    }

    # Resolve contact and flow first (needed by other sections)
    contact = if has_contact_section?(sections), do: resolve_contact(opts), else: nil
    flow = if has_flow_section?(sections), do: resolve_flow(opts), else: nil

    opts = Map.merge(opts, %{contact: contact, flow: flow})

    # Run independent queries in parallel
    # Each spawned task needs organization_id set in its process dictionary
    tasks =
      sections
      |> Enum.map(fn section ->
        Task.async(fn ->
          Repo.put_organization_id(organization_id)
          {section, fetch_section(section, opts)}
        end)
      end)

    results =
      tasks
      |> Task.await_many(15_000)
      |> Map.new()

    # Build diagnostics (computed, not a direct DB query)
    diagnostics =
      if "DIAGNOSTICS" in sections or include == nil do
        compute_diagnostics(contact, flow, opts)
      else
        nil
      end

    response = %{
      contact_info: Map.get(results, "CONTACT_INFO"),
      contact_history: Map.get(results, "CONTACT_HISTORY", []),
      messages: Map.get(results, "MESSAGES", []),
      flow_info: Map.get(results, "FLOW_INFO"),
      flow_revisions: Map.get(results, "FLOW_REVISIONS", []),
      flow_contexts: Map.get(results, "FLOW_CONTEXTS", []),
      flow_results: Map.get(results, "FLOW_RESULTS", []),
      notifications: Map.get(results, "NOTIFICATIONS", []),
      triggers: Map.get(results, "TRIGGERS", []),
      oban_jobs: Map.get(results, "OBAN_JOBS", []),
      groups: Map.get(results, "GROUPS", []),
      contact_groups: Map.get(results, "CONTACT_GROUPS", []),
      tags: Map.get(results, "TAGS", []),
      templates: Map.get(results, "TEMPLATES", []),
      wa_messages: Map.get(results, "WA_MESSAGES", []),
      tickets: Map.get(results, "TICKETS", []),
      diagnostics: diagnostics
    }

    {:ok, response}
  end

  # --- Section resolution ---

  defp resolve_sections(nil, nil, nil) do
    ["NOTIFICATIONS", "OBAN_JOBS", "DIAGNOSTICS"]
  end

  defp resolve_sections(nil, contact_filter, flow_filter) do
    sections =
      if(contact_filter, do: @contact_sections, else: []) ++
        if(flow_filter, do: @flow_sections, else: []) ++
        ["NOTIFICATIONS", "OBAN_JOBS", "GROUPS", "TEMPLATES", "DIAGNOSTICS"]

    sections |> Enum.uniq()
  end

  defp resolve_sections(include, _contact_filter, _flow_filter) when is_list(include) do
    (Enum.map(include, &to_string/1) ++ ["DIAGNOSTICS"])
    |> Enum.filter(&(&1 in @all_sections or &1 == "DIAGNOSTICS"))
    |> Enum.uniq()
  end

  defp has_contact_section?(sections) do
    Enum.any?(sections, &(&1 in @contact_sections))
  end

  defp has_flow_section?(sections) do
    Enum.any?(sections, &(&1 in @flow_sections))
  end

  # --- Contact / Flow resolution ---

  defp resolve_contact(%{contact_filter: nil}), do: nil

  defp resolve_contact(%{organization_id: org_id, contact_filter: filter}) do
    query = from(c in Contact, where: c.organization_id == ^org_id)

    query =
      cond do
        Map.has_key?(filter, :id) ->
          from(c in query, where: c.id == ^filter.id)

        Map.has_key?(filter, :phone) ->
          from(c in query, where: c.phone == ^filter.phone)

        Map.has_key?(filter, :name) ->
          from(c in query, where: ilike(c.name, ^"%#{filter.name}%"))

        true ->
          query
      end

    Repo.one(query)
  end

  defp resolve_flow(%{flow_filter: nil}), do: nil

  defp resolve_flow(%{organization_id: org_id, flow_filter: filter}) do
    query = from(f in Flow, where: f.organization_id == ^org_id)

    query =
      cond do
        Map.has_key?(filter, :id) ->
          from(f in query, where: f.id == ^filter.id)

        Map.has_key?(filter, :uuid) ->
          from(f in query, where: f.uuid == ^filter.uuid)

        Map.has_key?(filter, :name) ->
          from(f in query, where: ilike(f.name, ^"%#{filter.name}%"))

        true ->
          query
      end

    Repo.one(query)
  end

  # --- Section fetchers ---

  defp fetch_section("CONTACT_INFO", %{contact: nil}), do: nil

  defp fetch_section("CONTACT_INFO", %{contact: contact}) do
    %{
      id: contact.id,
      name: contact.name,
      phone: contact.phone,
      status: contact.status,
      bsp_status: contact.bsp_status,
      optin_status: contact.optin_status,
      optin_time: contact.optin_time,
      optout_time: contact.optout_time,
      optin_method: contact.optin_method,
      last_message_at: contact.last_message_at,
      last_communication_at: contact.last_communication_at,
      fields: contact.fields,
      settings: contact.settings,
      inserted_at: contact.inserted_at,
      updated_at: contact.updated_at
    }
  end

  defp fetch_section("CONTACT_HISTORY", %{contact: nil}), do: []

  defp fetch_section("CONTACT_HISTORY", %{
         organization_id: org_id,
         contact: contact,
         time_range: time_range,
         limit: limit
       }) do
    from(ch in ContactHistory,
      where: ch.organization_id == ^org_id,
      where: ch.contact_id == ^contact.id,
      where: ch.inserted_at >= ^time_range,
      order_by: [desc: ch.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(fn ch ->
      %{
        id: ch.id,
        event_type: ch.event_type,
        event_label: ch.event_label,
        event_meta: ch.event_meta,
        inserted_at: ch.inserted_at
      }
    end)
  end

  defp fetch_section("MESSAGES", %{contact: nil}), do: []

  defp fetch_section("MESSAGES", %{
         organization_id: org_id,
         contact: contact,
         time_range: time_range,
         limit: limit
       }) do
    from(m in Message,
      where: m.organization_id == ^org_id,
      where: m.contact_id == ^contact.id,
      where: m.inserted_at >= ^time_range,
      order_by: [desc: m.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(fn m ->
      %{
        id: m.id,
        body: m.body,
        type: m.type,
        flow: m.flow,
        status: m.status,
        bsp_status: m.bsp_status,
        errors: m.errors,
        send_at: m.send_at,
        sent_at: m.sent_at,
        message_number: m.message_number,
        flow_id: m.flow_id,
        sender_id: m.sender_id,
        contact_id: m.contact_id,
        inserted_at: m.inserted_at,
        updated_at: m.updated_at
      }
    end)
  end

  defp fetch_section("FLOW_INFO", %{flow: nil}), do: nil

  defp fetch_section("FLOW_INFO", %{flow: flow}) do
    %{
      id: flow.id,
      name: flow.name,
      uuid: flow.uuid,
      keywords: flow.keywords,
      is_active: flow.is_active,
      is_pinned: flow.is_pinned,
      is_background: flow.is_background,
      respond_other: flow.respond_other,
      ignore_keywords: flow.ignore_keywords,
      version_number: flow.version_number,
      inserted_at: flow.inserted_at,
      updated_at: flow.updated_at
    }
  end

  defp fetch_section("FLOW_REVISIONS", %{flow: nil}), do: []

  defp fetch_section("FLOW_REVISIONS", %{
         organization_id: org_id,
         flow: flow,
         limit: limit
       }) do
    from(fr in FlowRevision,
      where: fr.organization_id == ^org_id,
      where: fr.flow_id == ^flow.id,
      order_by: [desc: fr.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(fn fr ->
      %{
        id: fr.id,
        flow_id: fr.flow_id,
        definition: Jason.encode!(fr.definition),
        status: fr.status,
        version: fr.version,
        revision_number: fr.revision_number,
        inserted_at: fr.inserted_at,
        updated_at: fr.updated_at
      }
    end)
  end

  defp fetch_section("FLOW_CONTEXTS", %{organization_id: org_id} = opts) do
    contact = Map.get(opts, :contact)
    flow = Map.get(opts, :flow)
    time_range = Map.get(opts, :time_range)
    limit = Map.get(opts, :limit, @default_limit)

    if is_nil(contact) and is_nil(flow),
      do: [],
      else: do_fetch_flow_contexts(org_id, contact, flow, time_range, limit)
  end

  defp do_fetch_flow_contexts(org_id, contact, flow, time_range, limit) do
    query =
      from(fc in FlowContext,
        where: fc.organization_id == ^org_id,
        where: fc.inserted_at >= ^time_range,
        order_by: [desc: fc.inserted_at],
        limit: ^limit,
        preload: [:flow, :contact]
      )

    query = if contact, do: from(fc in query, where: fc.contact_id == ^contact.id), else: query
    query = if flow, do: from(fc in query, where: fc.flow_id == ^flow.id), else: query

    Repo.all(query)
    |> Enum.map(fn fc ->
      %{
        id: fc.id,
        flow_id: fc.flow_id,
        flow_name: if(Ecto.assoc_loaded?(fc.flow) and fc.flow, do: fc.flow.name, else: nil),
        flow_uuid: fc.flow_uuid,
        contact_id: fc.contact_id,
        contact_name:
          if(Ecto.assoc_loaded?(fc.contact) and fc.contact, do: fc.contact.name, else: nil),
        contact_phone:
          if(Ecto.assoc_loaded?(fc.contact) and fc.contact, do: fc.contact.phone, else: nil),
        status: fc.status,
        node_uuid: fc.node_uuid,
        parent_id: fc.parent_id,
        results: fc.results,
        is_killed: fc.is_killed,
        is_background_flow: fc.is_background_flow,
        is_await_result: fc.is_await_result,
        wakeup_at: fc.wakeup_at,
        completed_at: fc.completed_at,
        inserted_at: fc.inserted_at,
        updated_at: fc.updated_at
      }
    end)
  end

  defp fetch_section("FLOW_RESULTS", %{organization_id: org_id} = opts) do
    contact = Map.get(opts, :contact)
    flow = Map.get(opts, :flow)
    time_range = Map.get(opts, :time_range)
    limit = Map.get(opts, :limit, @default_limit)

    if is_nil(contact) and is_nil(flow),
      do: [],
      else: do_fetch_flow_results(org_id, contact, flow, time_range, limit)
  end

  defp do_fetch_flow_results(org_id, contact, flow, time_range, limit) do
    query =
      from(fr in FlowResult,
        where: fr.organization_id == ^org_id,
        where: fr.inserted_at >= ^time_range,
        order_by: [desc: fr.inserted_at],
        limit: ^limit,
        preload: [:flow, :contact]
      )

    query = if contact, do: from(fr in query, where: fr.contact_id == ^contact.id), else: query
    query = if flow, do: from(fr in query, where: fr.flow_id == ^flow.id), else: query

    Repo.all(query)
    |> Enum.map(fn fr ->
      %{
        id: fr.id,
        flow_id: fr.flow_id,
        flow_name: if(Ecto.assoc_loaded?(fr.flow) and fr.flow, do: fr.flow.name, else: nil),
        contact_id: fr.contact_id,
        contact_name:
          if(Ecto.assoc_loaded?(fr.contact) and fr.contact, do: fr.contact.name, else: nil),
        results: fr.results,
        inserted_at: fr.inserted_at,
        updated_at: fr.updated_at
      }
    end)
  end

  defp fetch_section("NOTIFICATIONS", %{
         organization_id: org_id,
         time_range: time_range,
         limit: limit
       }) do
    from(n in Notification,
      where: n.organization_id == ^org_id,
      where: n.inserted_at >= ^time_range,
      order_by: [desc: n.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(fn n ->
      %{
        id: n.id,
        category: n.category,
        message: n.message,
        severity: n.severity,
        entity: n.entity,
        is_read: n.is_read,
        inserted_at: n.inserted_at,
        updated_at: n.updated_at
      }
    end)
  end

  defp fetch_section("TRIGGERS", %{flow: nil}), do: []

  defp fetch_section("TRIGGERS", %{
         organization_id: org_id,
         flow: flow,
         limit: limit
       }) do
    from(t in Trigger,
      where: t.organization_id == ^org_id,
      where: t.flow_id == ^flow.id,
      order_by: [desc: t.inserted_at],
      limit: ^limit,
      preload: [:flow]
    )
    |> Repo.all()
    |> Enum.map(fn t ->
      %{
        id: t.id,
        name: t.name,
        flow_id: t.flow_id,
        flow_name: if(Ecto.assoc_loaded?(t.flow) and t.flow, do: t.flow.name, else: nil),
        start_at: t.start_at,
        end_date: t.end_date,
        is_active: t.is_active,
        is_repeating: t.is_repeating,
        frequency: t.frequency,
        days: t.days,
        inserted_at: t.inserted_at
      }
    end)
  end

  defp fetch_section("OBAN_JOBS", %{
         organization_id: org_id,
         time_range: time_range,
         limit: limit
       }) do
    oban_prefix = Application.get_env(:glific, Oban)[:prefix] || "public"

    from(j in Oban.Job,
      where: fragment("(?->>'organization_id')::bigint = ?", j.args, ^org_id),
      where: j.inserted_at >= ^time_range,
      order_by: [desc: j.inserted_at],
      limit: ^limit
    )
    |> Ecto.Query.put_query_prefix(oban_prefix)
    |> Repo.all(skip_organization_id: true)
    |> Enum.map(fn j ->
      %{
        id: j.id,
        state: j.state,
        queue: j.queue,
        worker: j.worker,
        args: j.args,
        errors: j.errors,
        attempt: j.attempt,
        max_attempts: j.max_attempts,
        inserted_at: j.inserted_at,
        scheduled_at: j.scheduled_at,
        completed_at: j.completed_at
      }
    end)
  end

  defp fetch_section("GROUPS", %{organization_id: org_id, limit: limit}) do
    from(g in Group,
      where: g.organization_id == ^org_id,
      order_by: [desc: g.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(fn g ->
      %{
        id: g.id,
        label: g.label,
        description: g.description,
        is_restricted: g.is_restricted,
        inserted_at: g.inserted_at
      }
    end)
  end

  defp fetch_section("CONTACT_GROUPS", %{contact: nil}), do: []

  defp fetch_section("CONTACT_GROUPS", %{
         organization_id: org_id,
         contact: contact
       }) do
    from(g in Group,
      join: cg in "contacts_groups",
      on: cg.group_id == g.id,
      where: cg.contact_id == ^contact.id,
      where: g.organization_id == ^org_id,
      select: %{
        group_id: g.id,
        group_label: g.label,
        inserted_at: cg.inserted_at
      }
    )
    |> Repo.all()
  end

  defp fetch_section("TAGS", %{organization_id: org_id, limit: limit}) do
    from(t in Tag,
      where: t.organization_id == ^org_id,
      order_by: [desc: t.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(fn t ->
      %{
        id: t.id,
        label: t.label,
        description: t.description,
        inserted_at: t.inserted_at
      }
    end)
  end

  defp fetch_section("TEMPLATES", %{organization_id: org_id, limit: limit}) do
    from(st in SessionTemplate,
      where: st.organization_id == ^org_id,
      order_by: [desc: st.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(fn st ->
      %{
        id: st.id,
        label: st.label,
        body: st.body,
        type: st.type,
        shortcode: st.shortcode,
        status: st.status,
        is_hsm: st.is_hsm,
        is_active: st.is_active,
        number_parameters: st.number_parameters,
        category: st.category,
        inserted_at: st.inserted_at
      }
    end)
  end

  defp fetch_section("WA_MESSAGES", %{contact: nil}), do: []

  defp fetch_section("WA_MESSAGES", %{
         organization_id: org_id,
         contact: contact,
         time_range: time_range,
         limit: limit
       }) do
    from(wm in WAMessage,
      where: wm.organization_id == ^org_id,
      where: wm.contact_id == ^contact.id,
      where: wm.inserted_at >= ^time_range,
      order_by: [desc: wm.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(fn wm ->
      %{
        id: wm.id,
        body: wm.body,
        type: wm.type,
        status: wm.status,
        bsp_status: wm.bsp_status,
        contact_id: wm.contact_id,
        flow: wm.flow,
        inserted_at: wm.inserted_at
      }
    end)
  end

  defp fetch_section("TICKETS", %{contact: nil}), do: []

  defp fetch_section("TICKETS", %{
         organization_id: org_id,
         contact: contact,
         time_range: time_range,
         limit: limit
       }) do
    from(t in Ticket,
      where: t.organization_id == ^org_id,
      where: t.contact_id == ^contact.id,
      where: t.inserted_at >= ^time_range,
      order_by: [desc: t.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(fn t ->
      %{
        id: t.id,
        body: t.body,
        topic: t.topic,
        status: t.status,
        remarks: t.remarks,
        contact_id: t.contact_id,
        user_id: t.user_id,
        inserted_at: t.inserted_at,
        updated_at: t.updated_at
      }
    end)
  end

  # Catch-all for sections not yet implemented or unknown
  defp fetch_section(_section, _opts), do: nil

  # --- Diagnostics ---

  defp compute_diagnostics(contact, flow, opts) do
    org_id = opts.organization_id
    time_range = opts.time_range

    contact_opted_in = if contact, do: contact.optin_status == true, else: nil

    contact_session_active =
      if contact && contact.last_message_at do
        DateTime.diff(DateTime.utc_now(), contact.last_message_at, :hour) < 24
      else
        nil
      end

    contact_in_active_flow =
      if contact do
        from(fc in FlowContext,
          where: fc.organization_id == ^org_id,
          where: fc.contact_id == ^contact.id,
          where: is_nil(fc.completed_at),
          where: fc.is_killed == false,
          select: count(fc.id)
        )
        |> Repo.one() > 0
      else
        nil
      end

    flow_is_published =
      if flow do
        from(fr in FlowRevision,
          where: fr.flow_id == ^flow.id,
          where: fr.organization_id == ^org_id,
          where: fr.status == "published",
          select: true,
          limit: 1
        )
        |> Repo.one()
        |> is_truthy()
      else
        nil
      end

    flow_is_active = if flow, do: flow.is_active, else: nil

    recent_error_count =
      from(n in Notification,
        where: n.organization_id == ^org_id,
        where: n.inserted_at >= ^time_range,
        where: n.severity in ^["error", "critical", "Error", "Critical"],
        select: count(n.id)
      )
      |> Repo.one()

    oban_prefix = Application.get_env(:glific, Oban)[:prefix] || "public"

    pending_oban_jobs =
      from(j in Oban.Job,
        where: fragment("(?->>'organization_id')::bigint = ?", j.args, ^org_id),
        where: j.state in ["available", "scheduled", "executing"],
        select: count(j.id)
      )
      |> Ecto.Query.put_query_prefix(oban_prefix)
      |> Repo.one(skip_organization_id: true)

    %{
      contact_opted_in: contact_opted_in,
      contact_session_active: contact_session_active,
      contact_in_active_flow: contact_in_active_flow,
      flow_is_published: flow_is_published,
      flow_is_active: flow_is_active,
      recent_error_count: recent_error_count,
      pending_oban_jobs: pending_oban_jobs
    }
  end

  # --- Helpers ---

  defp is_truthy(nil), do: false
  defp is_truthy(_), do: true

  defp parse_time_range("1h"), do: DateTime.add(DateTime.utc_now(), -1, :hour)
  defp parse_time_range("3d"), do: DateTime.add(DateTime.utc_now(), -3, :day)
  defp parse_time_range("7d"), do: DateTime.add(DateTime.utc_now(), -7, :day)
  defp parse_time_range("30d"), do: DateTime.add(DateTime.utc_now(), -30, :day)
  defp parse_time_range(_), do: DateTime.add(DateTime.utc_now(), -24, :hour)
end
