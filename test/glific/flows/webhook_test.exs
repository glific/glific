defmodule Glific.Flows.WebhookTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Fixtures,
    Flows.WebhookLog
  }

  describe "webhook" do
  end

  describe "webhook logs" do
    @valid_attrs %{
      url: "some url",
      method: "GET",
      request_headers: %{},
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
  end
end
