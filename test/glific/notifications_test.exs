defmodule Glific.NotificationTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Fixtures,
    Notifications,
    Notifications.Notification
  }

  describe "notifications" do
    @valid_attrs %{
      category: "Partner",
      message: "Disabling GCS. Billing account is disabled",
      severity: "Warning",
      entity: %{
        id: 5,
        shortcode: "google_cloud_storage"
      }
    }
    @valid_more_attrs %{
      category: "Credentials",
      message: "Disabling BigQuery. Billing account is disabled",
      severity: "Critical",
      entity: %{
        id: 5,
        shortcode: "bigquery"
      }
    }
    @update_attrs %{
      category: "Partner",
      severity: "Critical",
      message: "Disabling GCS. Billing account is disabled",
      entity: %{
        id: 3,
        shortcode: "google_cloud_storage"
      }
    }
    @invalid_attrs %{
      category: nil,
      message: nil,
      entity: nil
    }
  end

  test "count_notifications/1 returns count of all notifications", attrs do
    notification_count = Notifications.count_notifications(%{filter: attrs})

    _notification_1 = Fixtures.notification_fixture(Map.merge(attrs, @valid_attrs))

    assert Notifications.count_notifications(%{filter: attrs}) == notification_count + 1

    _notification_3 = Fixtures.notification_fixture(Map.merge(attrs, @valid_more_attrs))

    assert Notifications.count_notifications(%{filter: attrs}) == notification_count + 2

    assert Notifications.count_notifications(%{
             filter: Map.merge(attrs, %{category: "Partner"})
           }) == 1
  end

  test "list_notifications/1 returns all notifications",
       %{organization_id: organization_id} = attrs do
    notification = Fixtures.notification_fixture(%{organization_id: organization_id})

    [notification_list] =
      Enum.filter(
        Notifications.list_notifications(%{filter: attrs}),
        fn t -> t.category == notification.category end
      )

    assert notification_list.category == notification.category
    assert notification_list.id == notification.id
    assert notification_list.message == notification.message
    assert notification_list.severity == notification.severity
  end

  test "create_notification/1 with valid data creates a extension", %{
    organization_id: organization_id
  } do
    attrs = Map.merge(@valid_attrs, %{organization_id: organization_id, severity: "Critical"})
    assert {:ok, %Notification{} = notification} = Notifications.create_notification(attrs)
    assert notification.category == "Partner"
    assert notification.message == "Disabling GCS. Billing account is disabled"
  end

  test "create_notification/1 with invalid data returns error changeset", %{
    organization_id: organization_id
  } do
    attrs = Map.merge(@invalid_attrs, %{organization_id: organization_id})

    assert {:error, %Ecto.Changeset{}} = Notifications.create_notification(attrs)
  end

  test "update_notification/2 with valid data updates the extension", %{
    organization_id: organization_id
  } do
    attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})

    assert {:ok, %Notification{} = notification} = Notifications.create_notification(attrs)

    attrs = Map.merge(@update_attrs, %{severity: "Warning"})

    assert {:ok, %Notification{} = updated_notification} =
             Notifications.update_notification(notification, attrs)

    assert updated_notification.category == "Partner"
    assert updated_notification.message == "Disabling GCS. Billing account is disabled"
  end
end
