defmodule GlificWeb.Schema.NotificationTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.Fixtures

  load_gql(:count, GlificWeb.Schema, "assets/gql/notifications/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/notifications/list.gql")

  test "notifications field returns list of notifications", %{staff: user} = attrs do
    notify = Fixtures.notification_fixture(attrs)
    result = auth_query_gql_by(:list, user, variables: %{})
    assert {:ok, query_data} = result
    notifications = get_in(query_data, [:data, "notifications"])
    assert length(notifications) > 0
    [notification | _] = notifications
    assert notification["category"] == notify.category
  end

  # test "notifications field returns list of notifications in desc order", %{staff: user} = attrs do
  #   _wl_1 = Fixtures.notification_fixture(attrs)
  #   :timer.sleep(1000)
  #   valid_attrs_2 = Map.merge(attrs, %{category: "test_category_2", status_code: 500})
  #   wl_2 = Fixtures.notification_fixture(valid_attrs_2)

  #   result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "DESC"}})
  #   assert {:ok, query_data} = result
  #   notifications = get_in(query_data, [:data, "notifications"])
  #   assert length(notifications) > 0
  #   [notification | _] = notifications
  #   assert notification["category"] == wl_2.category
  # end

  # test "notifications field returns list of notifications in various filters",
  #      %{staff: user} = attrs do
  #   wl_1 = Fixtures.notification_fixture(attrs)
  #   valid_attrs_2 = Map.merge(attrs, %{category: "test_category_2", status_code: 500})
  #   _wl_2 = Fixtures.notification_fixture(valid_attrs_2)

  #   result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"category" => wl_1.category}})
  #   assert {:ok, query_data} = result
  #   notifications = get_in(query_data, [:data, "notifications"])
  #   assert length(notifications) > 0
  #   [notification | _] = notifications
  #   assert get_in(notification, ["category"]) == wl_1.category

  #   result =
  #     auth_query_gql_by(:list, user,
  #       variables: %{"filter" => %{"status_code" => wl_1.status_code}}
  #     )

  #   assert {:ok, query_data} = result
  #   notifications = get_in(query_data, [:data, "notifications"])
  #   assert length(notifications) > 0
  #   [notification | _] = notifications
  #   assert get_in(notification, ["statusCode"]) == wl_1.status_code
  # end

  # test "notifications field obeys limit and offset", %{staff: user} = attrs do
  #   _wl_1 = Fixtures.notification_fixture(attrs)
  #   valid_attrs_2 = Map.merge(attrs, %{category: "test_category_2", status_code: 500})
  #   _wl_2 = Fixtures.notification_fixture(valid_attrs_2)

  #   result =
  #     auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})

  #   assert {:ok, query_data} = result
  #   assert length(get_in(query_data, [:data, "notifications"])) == 1

  #   result =
  #     auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1, "offset" => 1}})

  #   assert {:ok, query_data} = result

  #   notifications = get_in(query_data, [:data, "notifications"])
  #   assert length(notifications) == 1
  # end

  # test "count returns the number of notifications", %{staff: user} = attrs do
  #   _wl_1 = Fixtures.notification_fixture(attrs)
  #   valid_attrs_2 = Map.merge(attrs, %{category: "test_category_2"})
  #   wl_2 = Fixtures.notification_fixture(valid_attrs_2)

  #   {:ok, query_data} = auth_query_gql_by(:count, user)
  #   assert get_in(query_data, [:data, "countnotifications"]) == 2

  #   {:ok, query_data} =
  #     auth_query_gql_by(:count, user,
  #       variables: %{"filter" => %{"category" => "This notification doesn't exist"}}
  #     )

  #   assert get_in(query_data, [:data, "countnotifications"]) == 0

  #   {:ok, query_data} =
  #     auth_query_gql_by(:count, user, variables: %{"filter" => %{"category" => wl_2.category}})

  #   assert get_in(query_data, [:data, "countnotifications"]) == 1
  # end
end
