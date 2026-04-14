defmodule Glific.StatsTest do
  use Glific.DataCase

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Fixtures,
    Flows.FlowContext,
    MessageConversations,
    Messages.Message,
    Messages.MessageConversation,
    Stats,
    Users.User
  }

  defp dt(date, time), do: DateTime.new!(date, time, "Etc/UTC")

  defp update_contact(contact, updates) do
    Repo.update_all(from(c in Contact, where: c.id == ^contact.id), set: updates)
  end

  defp update_message(message, updates) do
    Repo.update_all(from(m in Message, where: m.id == ^message.id), set: updates)
  end

  defp update_message_conversation(conversation, updates) do
    Repo.update_all(from(c in MessageConversation, where: c.id == ^conversation.id), set: updates)
  end

  defp update_flow_context(flow_context, updates) do
    Repo.update_all(from(fc in FlowContext, where: fc.id == ^flow_context.id), set: updates)
  end

  defp update_user(user, updates) do
    Repo.update_all(from(u in User, where: u.id == ^user.id), set: updates)
  end

  defp create_contact(org_id, suffix) do
    {:ok, contact} =
      Contacts.create_contact(%{
        name: "Stats Contact #{suffix}",
        phone: "91991#{suffix}",
        organization_id: org_id
      })

    contact
  end

  defp create_message(org_id, suffix, flow, is_hsm) do
    sender = Fixtures.contact_fixture(%{organization_id: org_id, phone: "91881#{suffix}"})
    receiver = Fixtures.contact_fixture(%{organization_id: org_id, phone: "91771#{suffix}"})

    Fixtures.message_fixture(%{
      organization_id: org_id,
      sender_id: sender.id,
      receiver_id: receiver.id,
      contact_id: receiver.id,
      flow: flow,
      is_hsm: is_hsm
    })
  end

  defp create_message_conversation(org_id, suffix) do
    message = create_message(org_id, "66#{suffix}", :inbound, false)

    {:ok, message_conversation} =
      MessageConversations.create_message_conversation(%{
        organization_id: org_id,
        message_id: message.id,
        conversation_id: "stats-conv-#{suffix}",
        deduction_type: "conversation",
        payload: %{},
        is_billable: false
      })

    message_conversation
  end

  defp create_flow_context(org_id, suffix) do
    contact = Fixtures.contact_fixture(%{organization_id: org_id, phone: "91551#{suffix}"})

    {:ok, flow_context} =
      %{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        node_uuid: Ecto.UUID.generate(),
        status: "published",
        uuid_map: %{"k#{suffix}" => "v#{suffix}"},
        contact_id: contact.id,
        organization_id: org_id
      }
      |> FlowContext.create_flow_context()

    flow_context
  end

  defp create_user(org_id, suffix) do
    Fixtures.user_fixture(%{
      organization_id: org_id,
      phone: "91661#{suffix}"
    })
  end

  defp fetch_single_stat!(org_id, period, date, hour \\ 0) do
    [stat] =
      Stats.list_stats(%{
        filter: %{
          organization_id: org_id,
          period: period,
          date: date,
          hour: hour
        }
      })

    stat
  end

  test "create and update stat", %{organization_id: organization_id} do
    attrs = %{organization_id: organization_id, period: "hour", hour: 0, date: ~D[2099-01-01]}
    assert {:ok, stat} = Stats.create_stat(attrs)
    assert stat.period == "hour"

    assert {:ok, updated} = Stats.update_stat(stat, %{period: "day"})
    assert updated.period == "day"
  end

  test "generate hourly stats with time boundaries across contacts, messages, conversations, flows and users",
       %{organization_id: organization_id} do
    date = ~D[2099-01-15]
    time = dt(date, ~T[10:30:00])
    start_dt = dt(date, ~T[10:00:00])
    end_usec = dt(date, ~T[10:59:59.999999])
    prev_usec = dt(date, ~T[09:59:59.999999])
    next_dt = dt(date, ~T[11:00:00])

    contact_start = create_contact(organization_id, "000001")
    contact_end = create_contact(organization_id, "000002")
    contact_prev = create_contact(organization_id, "000003")
    contact_next = create_contact(organization_id, "000004")

    update_contact(contact_start, last_message_at: start_dt)
    update_contact(contact_end, last_message_at: end_usec)
    update_contact(contact_prev, last_message_at: prev_usec)
    update_contact(contact_next, last_message_at: next_dt)

    msg_start = create_message(organization_id, "010001", :inbound, true)
    msg_end = create_message(organization_id, "010002", :outbound, false)
    msg_prev = create_message(organization_id, "010003", :inbound, true)
    msg_next = create_message(organization_id, "010004", :outbound, true)

    update_message(msg_start, inserted_at: start_dt)
    update_message(msg_end, inserted_at: end_usec)
    update_message(msg_prev, inserted_at: prev_usec)
    update_message(msg_next, inserted_at: next_dt)

    conv_start = create_message_conversation(organization_id, "020001")
    conv_end = create_message_conversation(organization_id, "020002")
    conv_prev = create_message_conversation(organization_id, "020003")
    conv_next = create_message_conversation(organization_id, "020004")

    update_message_conversation(conv_start, inserted_at: start_dt)
    update_message_conversation(conv_end, inserted_at: end_usec)
    update_message_conversation(conv_prev, inserted_at: prev_usec)
    update_message_conversation(conv_next, inserted_at: next_dt)

    flow_start = create_flow_context(organization_id, "030001")
    flow_end = create_flow_context(organization_id, "030002")
    flow_prev = create_flow_context(organization_id, "030003")
    flow_next = create_flow_context(organization_id, "030004")

    update_flow_context(flow_start, inserted_at: start_dt, completed_at: start_dt)
    update_flow_context(flow_end, inserted_at: end_usec, completed_at: end_usec)
    update_flow_context(flow_prev, inserted_at: prev_usec, completed_at: prev_usec)
    update_flow_context(flow_next, inserted_at: next_dt, completed_at: next_dt)

    user_start = create_user(organization_id, "040001")
    user_end = create_user(organization_id, "040002")
    user_prev = create_user(organization_id, "040003")
    user_next = create_user(organization_id, "040004")

    update_user(user_start, last_login_at: start_dt)
    update_user(user_end, last_login_at: end_usec)
    update_user(user_prev, last_login_at: prev_usec)
    update_user(user_next, last_login_at: next_dt)

    Stats.generate_stats([organization_id], false,
      time: time,
      day: false,
      week: false,
      month: false
    )

    stat = fetch_single_stat!(organization_id, "hour", date, 10)
    assert stat.contacts == 0
    assert stat.active == 2
    assert stat.messages == 2
    assert stat.inbound == 1
    assert stat.outbound == 1
    assert stat.hsm == 1
    assert stat.conversations == 2
    assert stat.flows_started == 2
    assert stat.flows_completed == 2
    assert stat.users == 2
  end

  test "generate_stats normalizes time by truncating to second and clearing minute and second", %{
    organization_id: organization_id
  } do
    date = ~D[2099-01-16]
    time = dt(date, ~T[10:59:59.987654])
    hour_start = dt(date, ~T[10:00:00])
    next_hour_usec = dt(date, ~T[11:00:00.500000])

    contact_in_hour = create_contact(organization_id, "050001")
    contact_next_hour = create_contact(organization_id, "050002")

    update_contact(contact_in_hour, last_message_at: hour_start)
    update_contact(contact_next_hour, last_message_at: next_hour_usec)

    Stats.generate_stats([organization_id], false,
      time: time,
      day: false,
      week: false,
      month: false
    )

    stat = fetch_single_stat!(organization_id, "hour", date, 10)

    assert stat.active == 1
  end

  test "generate daily stats with time boundaries across contacts, messages, conversations, flows and users",
       %{organization_id: organization_id} do
    date = ~D[2099-01-31]
    time = dt(date, ~T[23:00:00])
    start_dt = dt(date, ~T[00:00:00])
    end_usec = dt(date, ~T[23:59:59.999999])
    prev_usec = dt(Date.add(date, -1), ~T[23:59:59.999999])
    next_dt = dt(Date.add(date, 1), ~T[00:00:00])

    contact_start = create_contact(organization_id, "100001")
    contact_end = create_contact(organization_id, "100002")
    contact_prev = create_contact(organization_id, "100003")
    contact_next = create_contact(organization_id, "100004")

    update_contact(contact_start, inserted_at: start_dt, last_message_at: start_dt)
    update_contact(contact_end, inserted_at: end_usec, last_message_at: end_usec)
    update_contact(contact_prev, inserted_at: prev_usec, last_message_at: prev_usec)
    update_contact(contact_next, inserted_at: next_dt, last_message_at: next_dt)

    msg_start = create_message(organization_id, "110001", :inbound, true)
    msg_end = create_message(organization_id, "110002", :outbound, false)
    msg_prev = create_message(organization_id, "110003", :inbound, true)
    msg_next = create_message(organization_id, "110004", :outbound, true)

    update_message(msg_start, inserted_at: start_dt)
    update_message(msg_end, inserted_at: end_usec)
    update_message(msg_prev, inserted_at: prev_usec)
    update_message(msg_next, inserted_at: next_dt)

    conv_start = create_message_conversation(organization_id, "120001")
    conv_end = create_message_conversation(organization_id, "120002")
    conv_prev = create_message_conversation(organization_id, "120003")
    conv_next = create_message_conversation(organization_id, "120004")

    update_message_conversation(conv_start, inserted_at: start_dt)
    update_message_conversation(conv_end, inserted_at: end_usec)
    update_message_conversation(conv_prev, inserted_at: prev_usec)
    update_message_conversation(conv_next, inserted_at: next_dt)

    flow_start = create_flow_context(organization_id, "130001")
    flow_end = create_flow_context(organization_id, "130002")
    flow_prev = create_flow_context(organization_id, "130003")
    flow_next = create_flow_context(organization_id, "130004")

    update_flow_context(flow_start, inserted_at: start_dt, completed_at: start_dt)
    update_flow_context(flow_end, inserted_at: end_usec, completed_at: end_usec)
    update_flow_context(flow_prev, inserted_at: prev_usec, completed_at: prev_usec)
    update_flow_context(flow_next, inserted_at: next_dt, completed_at: next_dt)

    user_start = create_user(organization_id, "140001")
    user_end = create_user(organization_id, "140002")
    user_prev = create_user(organization_id, "140003")
    user_next = create_user(organization_id, "140004")

    update_user(user_start, last_login_at: start_dt)
    update_user(user_end, last_login_at: end_usec)
    update_user(user_prev, last_login_at: prev_usec)
    update_user(user_next, last_login_at: next_dt)

    Stats.generate_stats([organization_id], false,
      time: time,
      hour: false,
      week: false,
      month: false
    )

    stat = fetch_single_stat!(organization_id, "day", date)
    assert stat.contacts == 2
    assert stat.active == 2
    assert stat.messages == 2
    assert stat.inbound == 1
    assert stat.outbound == 1
    assert stat.hsm == 1
    assert stat.conversations == 2
    assert stat.flows_started == 2
    assert stat.flows_completed == 2
    assert stat.users == 2
  end

  test "generate weekly stats with boundaries and verify summary row permutations" do
    organization =
      Fixtures.organization_fixture(%{
        name: "Stats Weekly Org",
        shortcode: "statsweekly#{System.unique_integer([:positive])}"
      })

    organization_id = organization.id
    Repo.put_organization_id(organization_id)
    RepoReplica.put_organization_id(organization_id)

    week_anchor = dt(~D[2099-02-01], ~T[12:00:00])
    week_start = week_anchor |> Timex.beginning_of_week() |> DateTime.to_date()
    week_end = week_anchor |> Timex.end_of_week() |> DateTime.to_date()
    time = dt(week_end, ~T[23:00:00])
    start_dt = dt(week_start, ~T[00:00:00])
    end_usec = dt(week_end, ~T[23:59:59.999999])
    prev_usec = dt(Date.add(week_start, -1), ~T[23:59:59.999999])
    next_dt = dt(Date.add(week_end, 1), ~T[00:00:00])

    c1 = create_contact(organization_id, "200001")
    c2 = create_contact(organization_id, "200002")
    c3 = create_contact(organization_id, "200003")
    c4 = create_contact(organization_id, "200004")

    update_contact(c1, inserted_at: start_dt, last_message_at: start_dt, optin_time: start_dt)
    update_contact(c2, inserted_at: end_usec, last_message_at: end_usec, optout_time: end_usec)
    update_contact(c3, inserted_at: prev_usec, last_message_at: prev_usec, optin_time: prev_usec)
    update_contact(c4, inserted_at: next_dt, last_message_at: next_dt, optout_time: next_dt)

    msg_start = create_message(organization_id, "210001", :inbound, true)
    msg_end = create_message(organization_id, "210002", :outbound, false)
    msg_prev = create_message(organization_id, "210003", :inbound, true)
    msg_next = create_message(organization_id, "210004", :outbound, true)

    update_message(msg_start, inserted_at: start_dt)
    update_message(msg_end, inserted_at: end_usec)
    update_message(msg_prev, inserted_at: prev_usec)
    update_message(msg_next, inserted_at: next_dt)

    conv_start = create_message_conversation(organization_id, "220001")
    conv_end = create_message_conversation(organization_id, "220002")
    conv_prev = create_message_conversation(organization_id, "220003")
    conv_next = create_message_conversation(organization_id, "220004")

    update_message_conversation(conv_start, inserted_at: start_dt)
    update_message_conversation(conv_end, inserted_at: end_usec)
    update_message_conversation(conv_prev, inserted_at: prev_usec)
    update_message_conversation(conv_next, inserted_at: next_dt)

    flow_start = create_flow_context(organization_id, "230001")
    flow_end = create_flow_context(organization_id, "230002")
    flow_prev = create_flow_context(organization_id, "230003")
    flow_next = create_flow_context(organization_id, "230004")

    update_flow_context(flow_start, inserted_at: start_dt, completed_at: start_dt)
    update_flow_context(flow_end, inserted_at: end_usec, completed_at: end_usec)
    update_flow_context(flow_prev, inserted_at: prev_usec, completed_at: prev_usec)
    update_flow_context(flow_next, inserted_at: next_dt, completed_at: next_dt)

    user_start = create_user(organization_id, "240001")
    user_end = create_user(organization_id, "240002")
    user_prev = create_user(organization_id, "240003")
    user_next = create_user(organization_id, "240004")

    update_user(user_start, last_login_at: start_dt)
    update_user(user_end, last_login_at: end_usec)
    update_user(user_prev, last_login_at: prev_usec)
    update_user(user_next, last_login_at: next_dt)

    Stats.generate_stats([organization_id], false,
      time: time,
      hour: false,
      day: false,
      month: false
    )

    week_stat = fetch_single_stat!(organization_id, "week", week_start)
    summary_stat = fetch_single_stat!(organization_id, "summary", week_start)

    assert week_stat.contacts == 2
    assert week_stat.messages == 2
    assert week_stat.inbound == 1
    assert week_stat.outbound == 1
    assert week_stat.hsm == 1
    assert week_stat.conversations == 2
    assert week_stat.flows_started == 2
    assert week_stat.flows_completed == 2
    assert week_stat.users == 2

    # Summary spans all records in this test org, including contacts/users created implicitly by
    # fixtures: 4 explicit contacts + 8 from create_message + 8 from create_message_conversation
    # + 4 from create_flow_context = 24 contacts; users are 1 org fixture user + 4 explicit = 5.
    assert summary_stat.contacts == 24
    assert summary_stat.active == 24
    assert summary_stat.optin == 22
    assert summary_stat.optout == 2
    assert summary_stat.messages == 8
    assert summary_stat.inbound == 6
    assert summary_stat.outbound == 2
    assert summary_stat.hsm == 3
    assert summary_stat.conversations == 4
    assert summary_stat.flows_started == 0
    assert summary_stat.flows_completed == 0
    assert summary_stat.users == 5
  end

  test "generate monthly stats with boundaries and verify summary row insert" do
    organization =
      Fixtures.organization_fixture(%{
        name: "Stats Monthly Org",
        shortcode: "statsmonthly#{System.unique_integer([:positive])}"
      })

    organization_id = organization.id
    Repo.put_organization_id(organization_id)
    RepoReplica.put_organization_id(organization_id)

    month_start = ~D[2099-03-01]
    month_end = ~D[2099-03-31]
    time = dt(month_end, ~T[23:00:00])
    start_dt = dt(month_start, ~T[00:00:00])
    end_usec = dt(month_end, ~T[23:59:59.999999])
    prev_usec = dt(Date.add(month_start, -1), ~T[23:59:59.999999])
    next_dt = dt(Date.add(month_end, 1), ~T[00:00:00])

    c1 = create_contact(organization_id, "300001")
    c2 = create_contact(organization_id, "300002")
    c3 = create_contact(organization_id, "300003")
    c4 = create_contact(organization_id, "300004")

    update_contact(c1, inserted_at: start_dt, last_message_at: start_dt, optin_time: start_dt)
    update_contact(c2, inserted_at: end_usec, last_message_at: end_usec, optout_time: end_usec)
    update_contact(c3, inserted_at: prev_usec, last_message_at: prev_usec, optin_time: prev_usec)
    update_contact(c4, inserted_at: next_dt, last_message_at: next_dt, optout_time: next_dt)

    msg_start = create_message(organization_id, "310001", :inbound, true)
    msg_end = create_message(organization_id, "310002", :outbound, false)
    msg_prev = create_message(organization_id, "310003", :inbound, true)
    msg_next = create_message(organization_id, "310004", :outbound, true)

    update_message(msg_start, inserted_at: start_dt)
    update_message(msg_end, inserted_at: end_usec)
    update_message(msg_prev, inserted_at: prev_usec)
    update_message(msg_next, inserted_at: next_dt)

    conv_start = create_message_conversation(organization_id, "320001")
    conv_end = create_message_conversation(organization_id, "320002")
    conv_prev = create_message_conversation(organization_id, "320003")
    conv_next = create_message_conversation(organization_id, "320004")

    update_message_conversation(conv_start, inserted_at: start_dt)
    update_message_conversation(conv_end, inserted_at: end_usec)
    update_message_conversation(conv_prev, inserted_at: prev_usec)
    update_message_conversation(conv_next, inserted_at: next_dt)

    flow_start = create_flow_context(organization_id, "330001")
    flow_end = create_flow_context(organization_id, "330002")
    flow_prev = create_flow_context(organization_id, "330003")
    flow_next = create_flow_context(organization_id, "330004")

    update_flow_context(flow_start, inserted_at: start_dt, completed_at: start_dt)
    update_flow_context(flow_end, inserted_at: end_usec, completed_at: end_usec)
    update_flow_context(flow_prev, inserted_at: prev_usec, completed_at: prev_usec)
    update_flow_context(flow_next, inserted_at: next_dt, completed_at: next_dt)

    user_start = create_user(organization_id, "340001")
    user_end = create_user(organization_id, "340002")
    user_prev = create_user(organization_id, "340003")
    user_next = create_user(organization_id, "340004")

    update_user(user_start, last_login_at: start_dt)
    update_user(user_end, last_login_at: end_usec)
    update_user(user_prev, last_login_at: prev_usec)
    update_user(user_next, last_login_at: next_dt)

    Stats.generate_stats([organization_id], false,
      time: time,
      hour: false,
      day: false,
      week: false
    )

    month_stat = fetch_single_stat!(organization_id, "month", month_start)
    summary_stat = fetch_single_stat!(organization_id, "summary", month_start)

    assert month_stat.contacts == 2
    assert month_stat.messages == 2
    assert month_stat.inbound == 1
    assert month_stat.outbound == 1
    assert month_stat.hsm == 1
    assert month_stat.conversations == 2
    assert month_stat.flows_started == 2
    assert month_stat.flows_completed == 2
    assert month_stat.users == 2

    # Summary spans all records in this test org, including contacts/users created implicitly by
    # fixtures: 4 explicit contacts + 8 from create_message + 8 from create_message_conversation
    # + 4 from create_flow_context = 24 contacts; users are 1 org fixture user + 4 explicit = 5.
    assert summary_stat.contacts == 24
    assert summary_stat.active == 24
    assert summary_stat.optin == 22
    assert summary_stat.optout == 2
    assert summary_stat.messages == 8
    assert summary_stat.inbound == 6
    assert summary_stat.outbound == 2
    assert summary_stat.hsm == 3
    assert summary_stat.conversations == 4
    assert summary_stat.flows_started == 0
    assert summary_stat.flows_completed == 0
    assert summary_stat.users == 5
  end

  test "usage returns sum of messages and max users over day range", %{
    organization_id: organization_id
  } do
    now = Date.utc_today()

    {:ok, _} =
      Stats.create_stat(%{
        organization_id: organization_id,
        period: "day",
        date: Date.add(now, -2),
        messages: 10,
        users: 2
      })

    {:ok, _} =
      Stats.create_stat(%{
        organization_id: organization_id,
        period: "day",
        date: Date.add(now, -1),
        messages: 7,
        users: 4
      })

    {:ok, _} =
      Stats.create_stat(%{
        organization_id: organization_id,
        period: "hour",
        date: Date.add(now, -1),
        hour: 5,
        messages: 100,
        users: 100
      })

    assert %{messages: 17, users: 4} =
             Stats.usage(organization_id, Date.add(now, -2), Date.add(now, -1))
  end

  test "count_stats, list_stats filtering and reject_empty for missed used paths", %{
    organization_id: organization_id
  } do
    assert Stats.count_stats(%{filter: %{organization_id: organization_id}}) == 0

    assert {:ok, _} =
             Stats.create_stat(%{
               organization_id: organization_id,
               period: "hour",
               date: ~D[2099-05-01],
               hour: 7,
               messages: 3
             })

    assert Stats.count_stats(%{filter: %{organization_id: organization_id}}) == 1

    filtered =
      Stats.list_stats(%{
        filter: %{organization_id: organization_id, period: "hour", date: ~D[2099-05-01], hour: 7}
      })

    assert length(filtered) == 1
    assert Stats.list_stats(%{filter: %{organization_id: organization_id, period: "week"}}) == []

    assert [%{messages: 1}] =
             Stats.reject_empty(%{
               a: %{
                 contacts: 0,
                 active: 0,
                 optin: 0,
                 optout: 0,
                 messages: 0,
                 inbound: 0,
                 outbound: 0,
                 hsm: 0,
                 flows_started: 0,
                 flows_completed: 0,
                 conversations: 0
               },
               b: %{
                 contacts: 0,
                 active: 0,
                 optin: 0,
                 optout: 0,
                 messages: 1,
                 inbound: 0,
                 outbound: 0,
                 hsm: 0,
                 flows_started: 0,
                 flows_completed: 0,
                 conversations: 0
               }
             })
  end

  test "get_daily_stats, get_weekly_stats and get_monthly_stats return input when period is disabled",
       %{
         organization_id: organization_id
       } do
    base = %{test: :value}
    time = dt(~D[2099-06-30], ~T[23:00:00])
    opts = [time: time, date: DateTime.to_date(time), day: false, week: false, month: false]

    assert Stats.get_daily_stats(base, [organization_id], opts) == base
    assert Stats.get_weekly_stats(base, [organization_id], opts) == base
    assert Stats.get_monthly_stats(base, [organization_id], opts) == base
  end
end
