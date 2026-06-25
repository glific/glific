defmodule Glific.Flows.WebhookTimeoutTest do
  @moduledoc """
  Covers the async-webhook timeout path in FlowContext: when a flow parked at an async
  webhook node is woken with no callback message, it records a timeout on the webhook log
  and reports the timeout failure.
  """
  use Glific.DataCase, async: false

  alias Glific.Fixtures
  alias Glific.Flows.{Flow, FlowContext, WebhookLog}
  alias Glific.Repo

  test "an async webhook node woken with no callback records a timeout on the webhook log", %{
    organization_id: org_id
  } do
    # the failure branch may try to send a message downstream; keep it from hitting the network
    Tesla.Mock.mock_global(fn _ -> %Tesla.Env{status: 200, body: %{}} end)

    contact = Fixtures.contact_fixture(%{organization_id: org_id})
    flow = Flow.get_loaded_flow(org_id, "published", %{keyword: "call_and_wait"})
    [node | _] = flow.nodes

    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: contact.id,
        flow_id: flow.id,
        flow_uuid: flow.uuid,
        uuid_map: %{},
        organization_id: org_id,
        is_await_result: true,
        wakeup_at: DateTime.add(DateTime.utc_now(), -1),
        node_uuid: node.uuid
      })

    webhook_log =
      Fixtures.webhook_log_fixture(%{organization_id: org_id, flow_context_id: context.id})

    context = Repo.preload(context, [:contact, :flow])

    # Woken with no message simulates the Kaapi callback never arriving (timeout).
    FlowContext.wakeup_one(context)

    assert Repo.get!(WebhookLog, webhook_log.id).error ==
             "Timeout: taking long to process response"
  end
end
