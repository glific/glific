defmodule Glific.EraseTest do
  use Glific.DataCase

  alias Glific.{
    Erase,
    Fixtures,
    Flows.FlowRevision,
    Flows.WebhookLog,
    Notifications,
    Notifications.Notification,
    Repo
  }

  test "perform_periodic clears webhook log older than a month", attrs do
    Fixtures.webhook_log_fixture(attrs)
    time = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.update_all(WebhookLog,
      set: [
        inserted_at: Timex.shift(time, months: -2)
      ]
    )

    logs_count = WebhookLog.count_webhook_logs(%{filter: attrs})
    Erase.clean_old_records()
    assert WebhookLog.count_webhook_logs(%{filter: attrs}) == logs_count - 1
  end

  test "perform_periodic clears notifications log older than a month", attrs do
    Fixtures.notification_fixture(attrs)
    time = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.update_all(Notification,
      set: [
        inserted_at: Timex.shift(time, months: -2)
      ]
    )

    notification_count = Notifications.count_notifications(%{filter: attrs})
    Erase.clean_old_records()
    assert Notifications.count_notifications(%{filter: attrs}) == notification_count - 1
  end

  test "perform_periodic clears flow revisions with status as draft, and saving only recent 10",
       attrs do
    user = Repo.get_current_user()
    flow = Fixtures.flow_fixture(attrs)

    Enum.each(1..15, fn _x ->
      FlowRevision.create_flow_revision(%{
        definition: FlowRevision.default_definition(flow),
        flow_id: flow.id,
        user_id: user.id,
        organization_id: flow.organization_id
      })
    end)

    flow_revision_count = Repo.count_filter(%{}, FlowRevision, &Repo.filter_with/2)
    Erase.clean_old_records()
    assert Repo.count_filter(%{}, FlowRevision, &Repo.filter_with/2) == flow_revision_count - 6
  end
end
