defmodule GlificWeb.Schema.WebhookLogTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.Fixtures

  load_gql(:count, GlificWeb.Schema, "assets/gql/webhook_logs/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/webhook_logs/list.gql")

  test "webhook_logs field returns list of webhook_logs", %{staff: user} = attrs do
    wl = Fixtures.webhook_log_fixture(attrs)

    result = auth_query_gql_by(:list, user, variables: %{})
    assert {:ok, query_data} = result
    webhook_logs = get_in(query_data, [:data, "webhookLogs"])
    assert length(webhook_logs) > 0
    [webhook_log | _] = webhook_logs
    assert webhook_log["url"] == wl.url
  end

  test "webhook_logs field returns list of webhook_logs in desc order", %{staff: user} = attrs do
    _wl_1 = Fixtures.webhook_log_fixture(attrs)
    :timer.sleep(1000)
    valid_attrs_2 = Map.merge(attrs, %{url: "test_url_2", status_code: 500})
    wl_2 = Fixtures.webhook_log_fixture(valid_attrs_2)

    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "DESC"}})
    assert {:ok, query_data} = result
    webhook_logs = get_in(query_data, [:data, "webhookLogs"])
    assert length(webhook_logs) > 0
    [webhook_log | _] = webhook_logs
    assert webhook_log["url"] == wl_2.url
  end

  test "webhook_logs field returns list of webhook_logs in various filters",
       %{staff: user} = attrs do
    wl_1 = Fixtures.webhook_log_fixture(attrs)
    valid_attrs_2 = Map.merge(attrs, %{url: "test_url_2", status_code: 500})
    _wl_2 = Fixtures.webhook_log_fixture(valid_attrs_2)

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"url" => wl_1.url}})
    assert {:ok, query_data} = result
    webhook_logs = get_in(query_data, [:data, "webhookLogs"])
    assert length(webhook_logs) > 0
    [webhook_log | _] = webhook_logs
    assert get_in(webhook_log, ["url"]) == wl_1.url

    result =
      auth_query_gql_by(:list, user,
        variables: %{"filter" => %{"status_code" => wl_1.status_code}}
      )

    assert {:ok, query_data} = result
    webhook_logs = get_in(query_data, [:data, "webhookLogs"])
    assert length(webhook_logs) > 0
    [webhook_log | _] = webhook_logs
    assert get_in(webhook_log, ["statusCode"]) == wl_1.status_code
  end

  test "webhook_logs field obeys limit and offset", %{staff: user} = attrs do
    _wl_1 = Fixtures.webhook_log_fixture(attrs)
    valid_attrs_2 = Map.merge(attrs, %{url: "test_url_2", status_code: 500})
    _wl_2 = Fixtures.webhook_log_fixture(valid_attrs_2)

    result =
      auth_query_gql_by(:list, user,
        variables: %{"opts" => %{"limit" => 1, "offset" => 0}}
      )

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "webhookLogs"])) == 1

    result =
      auth_query_gql_by(:list, user,
        variables: %{"opts" => %{"limit" => 1, "offset" => 1}}
      )

    assert {:ok, query_data} = result

    webhook_logs = get_in(query_data, [:data, "webhookLogs"])
    assert length(webhook_logs) == 1
  end

  test "count returns the number of webhook_logs", %{staff: user} = attrs do
    _wl_1 = Fixtures.webhook_log_fixture(attrs)
    valid_attrs_2 = Map.merge(attrs, %{url: "test_url_2"})
    wl_2 = Fixtures.webhook_log_fixture(valid_attrs_2)

    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countWebhookLogs"]) == 2

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"url" => "This webhook_log doesn't exist"}}
      )

    assert get_in(query_data, [:data, "countWebhookLogs"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"url" => wl_2.url}})

    assert get_in(query_data, [:data, "countWebhookLogs"]) == 1
  end
end
