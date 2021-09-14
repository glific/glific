defmodule Glific.EraseTest do
  use Glific.DataCase

  alias Glific.{
    Erase,
    Fixtures,
    Flows.WebhookLog,
    Notifications.Notification,
    Notifications,
    Repo
  }

  test "perform_periodic with clears webhook log older than a month",
       %{
         organization_id: _organization_id
       } = attrs do
    Fixtures.webhook_log_fixture(attrs)
    time = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.update_all(WebhookLog,
      set: [
        inserted_at: Timex.shift(time, months: -2)
      ]
    )

    logs_count = WebhookLog.count_webhook_logs(%{filter: attrs})
    Erase.perform_periodic()
    assert WebhookLog.count_webhook_logs(%{filter: attrs}) == logs_count - 1
  end

  test "perform_periodic with clears notifications log older than a month",
       %{
         organization_id: _organization_id
       } = attrs do
    Fixtures.notification_fixture(attrs)
    time = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.update_all(Notification,
      set: [
        inserted_at: Timex.shift(time, months: -2)
      ]
    )

    notification_count = Notifications.count_notifications(%{filter: attrs})
    Erase.perform_periodic()
    assert Notifications.count_notifications(%{filter: attrs}) == notification_count - 1
  end
end
