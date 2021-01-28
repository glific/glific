defmodule Glific.Flows.WebhookTest do
  use Glific.DataCase, async: true

  alias Glific.Flows.{
    Action,
    FlowContext,
    Webhook,
    WebhookLog
  }

  alias Glific.{
    Fixtures,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    :ok
  end

  describe "webhook" do
    @results %{
      "content" => "Your score: 31 is not divisible by 2, 3, 5 or 7",
      "score" => "31",
      "status" => "5"
    }
    @action_body %{
      contact: "@contact",
      results: "@results",
      custom_key: "custom_value"
    }
    test "execute a webhook for post method should return the response body with results",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(@results)
          }
      end)

      attrs = %{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: Fixtures.contact_fixture(attrs).id,
        organization_id: attrs.organization_id
      }

      {:ok, context} = FlowContext.create_flow_context(attrs)
      context = Repo.preload(context, :contact)

      action = %Action{
        headers: %{"Accept" => "application/json"},
        method: "POST",
        url: "some url",
        body: Jason.encode!(@action_body)
      }

      assert Webhook.execute(action, context) == nil
      # we now need to wait for the Oban job and fire and then
      # check the results of the context
    end

    test "execute a webhook for post method should not break and update the webhook log in case of error",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 404,
            body: ""
          }
      end)

      attrs = %{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: Fixtures.contact_fixture(attrs).id,
        organization_id: attrs.organization_id
      }

      {:ok, context} = FlowContext.create_flow_context(attrs)
      context = Repo.preload(context, :contact)

      action = %Action{
        headers: %{"Accept" => "application/json"},
        method: "POST",
        url: "wrong url",
        body: Jason.encode!(@action_body)
      }

      assert Webhook.execute(action, context) == nil
    end
  end

  describe "webhook logs" do
    @valid_attrs %{
      url: "some url",
      method: "GET",
      request_headers: %{
        "Accept" => "application/json",
        "X-Glific-Signature" => "random signature"
      },
      request_json: %{}
    }
    @update_attrs %{
      response_json: %{},
      status_code: 200
    }

    test "create_webhook_log/1 with valid data creates a webhook_log",
         %{organization_id: _organization_id} = attrs do
      flow = Fixtures.flow_fixture(attrs)
      contact = Fixtures.contact_fixture(attrs)

      valid_attrs =
        @valid_attrs
        |> Map.put(:contact_id, contact.id)
        |> Map.put(:flow_id, flow.id)
        |> Map.put(:organization_id, flow.organization_id)

      assert {:ok, %WebhookLog{} = webhook_log} = WebhookLog.create_webhook_log(valid_attrs)
    end

    test "update_webhook_log/2 with valid data updates the webhook_log", attrs do
      flow = Fixtures.flow_fixture(attrs)
      contact = Fixtures.contact_fixture(attrs)

      valid_attrs =
        @valid_attrs
        |> Map.put(:contact_id, contact.id)
        |> Map.put(:flow_id, flow.id)
        |> Map.put(:organization_id, flow.organization_id)

      {:ok, webhook_log} = WebhookLog.create_webhook_log(valid_attrs)

      assert {:ok, %WebhookLog{} = webhook_log} =
               WebhookLog.update_webhook_log(webhook_log, @update_attrs)

      assert webhook_log.status_code == 200
    end

    test "list_webhook_logs/2", attrs do
      webhook_log = Fixtures.webhook_log_fixture(attrs)

      assert [Map.merge(webhook_log, %{status: "Success"})] ==
               WebhookLog.list_webhook_logs(%{filter: attrs})
    end

    test "list_webhook_logs/2 returns filtered logs", attrs do
      webhook_log_1 = Fixtures.webhook_log_fixture(attrs)
      :timer.sleep(1000)

      valid_attrs_2 = Map.merge(attrs, %{url: "test_url_2", status_code: 500})
      webhook_log_2 = Fixtures.webhook_log_fixture(valid_attrs_2)

      assert [Map.merge(webhook_log_2, %{status: "Error"})] ==
               WebhookLog.list_webhook_logs(%{filter: Map.merge(%{status_code: 500}, attrs)})

      assert [Map.merge(webhook_log_1, %{status: "Success"})] ==
               WebhookLog.list_webhook_logs(%{
                 filter: Map.merge(%{status_code: 200, status: "Success"}, attrs)
               })

      assert [Map.merge(webhook_log_1, %{status: "Success"})] ==
               WebhookLog.list_webhook_logs(%{filter: Map.merge(%{url: @valid_attrs.url}, attrs)})

      #  order by inserted at
      assert [
               Map.merge(webhook_log_2, %{status: "Error"}),
               Map.merge(webhook_log_1, %{status: "Success"})
             ] ==
               WebhookLog.list_webhook_logs(%{opts: %{order: :desc}, filter: attrs})
    end

    test "count_webhook_logs/0 returns count of all webhook logs", attrs do
      logs_count = WebhookLog.count_webhook_logs(%{filter: attrs})

      Fixtures.webhook_log_fixture(attrs)

      assert WebhookLog.count_webhook_logs(%{filter: attrs}) == logs_count + 1
    end
  end
end
