defmodule GlificWeb.Schema.NotificationTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.Fixtures

  load_gql(:count, GlificWeb.Schema, "assets/gql/notifications/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/notifications/list.gql")
  load_gql(:mark_as_read, GlificWeb.Schema, "assets/gql/notifications/mark_as_read.gql")

  test "notifications field returns list of notifications", %{staff: user} = attrs do
    notify = Fixtures.notification_fixture(attrs)
    result = auth_query_gql_by(:list, user, variables: %{})
    assert {:ok, query_data} = result
    notifications = get_in(query_data, [:data, "notifications"])
    assert length(notifications) > 0
    [notification | _] = notifications
    assert notification["category"] == notify.category
    assert notification["is_read"] == false
  end

  test "notifications field returns list of notifications in desc order",
       %{staff: user} = attrs do
    _notify_1 = Fixtures.notification_fixture(attrs)
    :timer.sleep(1000)

    valid_attrs_2 =
      Map.merge(attrs, %{category: "Provider Error", message: "No balance in wallet"})

    notify_2 = Fixtures.notification_fixture(valid_attrs_2)

    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "DESC"}})
    assert {:ok, query_data} = result
    notifications = get_in(query_data, [:data, "notifications"])
    assert length(notifications) > 0
    [notification | _] = notifications
    assert notification["category"] == notify_2.category
  end

  test "notifications field returns list of notifications in various filters",
       %{staff: user} = attrs do
    notify_1 = Fixtures.notification_fixture(attrs)

    valid_attrs_2 =
      Map.merge(attrs, %{category: "Provider Error", message: "No balance in wallet"})

    _notify_2 = Fixtures.notification_fixture(valid_attrs_2)

    result =
      auth_query_gql_by(:list, user, variables: %{"filter" => %{"category" => notify_1.category}})

    assert {:ok, query_data} = result
    notifications = get_in(query_data, [:data, "notifications"])
    assert length(notifications) > 0
    [notification | _] = notifications
    assert get_in(notification, ["category"]) == notify_1.category

    result =
      auth_query_gql_by(:list, user, variables: %{"filter" => %{"message" => notify_1.message}})

    assert {:ok, query_data} = result
    notifications = get_in(query_data, [:data, "notifications"])
    assert length(notifications) > 0
    [notification | _] = notifications
    assert get_in(notification, ["message"]) == notify_1.message

    result =
      auth_query_gql_by(:list, user, variables: %{"filter" => %{"is_read" => false}})
    assert {:ok, query_data} = result
    notifications = get_in(query_data, [:data, "notifications"])
    assert length(notifications) > 0

  end

  test "notifications field obeys limit and offset", %{staff: user} = attrs do
    _notify_1 = Fixtures.notification_fixture(attrs)

    valid_attrs_2 =
      Map.merge(attrs, %{category: "Provider Error", message: "No balance in wallet"})

    _notify_2 = Fixtures.notification_fixture(valid_attrs_2)

    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "notifications"])) == 1

    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1, "offset" => 1}})

    assert {:ok, query_data} = result

    notifications = get_in(query_data, [:data, "notifications"])
    assert length(notifications) == 1
  end

  test "count returns the number of notifications", %{staff: user} = attrs do
    _notify_1 = Fixtures.notification_fixture(attrs)
    valid_attrs_2 = Map.merge(attrs, %{category: "test_category_2"})
    notify_2 = Fixtures.notification_fixture(valid_attrs_2)

    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countNotifications"]) == 2

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"category" => "This notification doesn't exist"}}
      )

    assert get_in(query_data, [:data, "countNotifications"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"category" => notify_2.category}})

    assert get_in(query_data, [:data, "countNotifications"]) == 1
  end

  test "mark all the notification as read", %{staff: user} = attrs do
    Enum.each(0..5, fn _ -> Fixtures.notification_fixture(attrs) end)

    unread_notification =  Glific.Notifications.count_notifications(%{filter: %{is_read: false}})
    assert unread_notification > 0

    result = auth_query_gql_by(:mark_as_read, user, variables: %{})
    assert {:ok, _query_data} = result

    unread_notification =  Glific.Notifications.count_notifications(%{filter: %{is_read: false}})
    assert unread_notification == 0

  end

end
