defmodule Glific.Flows.WebhookResumeTest do
  @moduledoc """
  Covers which flow context an async webhook callback resumes: the context that made the call,
  and nothing else once that context has been replaced.
  """
  use Glific.DataCase, async: false

  alias Glific.Fixtures
  alias Glific.Flows.Flow
  alias Glific.Flows.FlowContext
  alias Glific.Flows.Webhook
  alias Glific.Flows.WebhookLog
  alias Glific.LlmCalls.LlmCall
  alias Glific.Repo

  setup %{organization_id: organization_id} do
    Tesla.Mock.mock_global(fn _ -> %Tesla.Env{status: 200, body: %{}} end)

    contact = Fixtures.contact_fixture(%{organization_id: organization_id})
    flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})

    %{contact: contact, flow: flow}
  end

  test "a callback resumes the context that made the call", %{
    organization_id: organization_id,
    contact: contact,
    flow: flow
  } do
    context = Fixtures.awaiting_flow_context_fixture(%{flow: flow, contact: contact})
    webhook_log = webhook_log_for(organization_id, context)
    newer = Fixtures.awaiting_flow_context_fixture(%{flow: flow, contact: contact})

    resume(organization_id, contact, flow, webhook_log.id, "answer")

    assert %{"answer" => _} = Repo.get!(FlowContext, context.id).results

    newer = Repo.get!(FlowContext, newer.id)
    assert newer.is_await_result
    refute Map.has_key?(newer.results, "answer")
  end

  test "a callback whose logged context belongs to another flow is dropped", %{
    organization_id: organization_id,
    contact: contact,
    flow: flow
  } do
    context = Fixtures.awaiting_flow_context_fixture(%{flow: flow, contact: contact})
    webhook_log = webhook_log_for(organization_id, context)
    other_flow = Fixtures.flow_fixture(%{organization_id: organization_id})

    resume(organization_id, contact, other_flow, webhook_log.id, "answer")

    context = Repo.get!(FlowContext, context.id)
    assert context.is_await_result
    refute Map.has_key?(context.results, "answer")
  end

  test "a dropped LLM callback still records the LLM call", %{
    organization_id: organization_id,
    contact: contact,
    flow: flow
  } do
    replaced = Fixtures.awaiting_flow_context_fixture(%{flow: flow, contact: contact})
    webhook_log = webhook_log_for(organization_id, replaced)
    {:ok, _} = FlowContext.update_flow_context(replaced, %{completed_at: DateTime.utc_now()})

    Webhook.resume(organization_id, %{"success" => true}, %{
      "contact_id" => contact.id,
      "flow_id" => flow.id,
      "webhook_log_id" => webhook_log.id,
      "call_type" => "llm"
    })

    assert [%LlmCall{contact_id: contact_id}] = Repo.all(LlmCall)
    assert contact_id == contact.id
  end

  test "a dropped LLM callback whose log belongs to another flow records nothing", %{
    organization_id: organization_id,
    contact: contact,
    flow: flow
  } do
    context = Fixtures.awaiting_flow_context_fixture(%{flow: flow, contact: contact})
    webhook_log = webhook_log_for(organization_id, context)
    other_flow = Fixtures.flow_fixture(%{organization_id: organization_id})

    Webhook.resume(organization_id, %{"success" => true}, %{
      "contact_id" => contact.id,
      "flow_id" => other_flow.id,
      "webhook_log_id" => webhook_log.id,
      "call_type" => "llm"
    })

    assert Repo.all(LlmCall) == []
  end

  test "a callback for a replaced context does not resume the context that replaced it", %{
    organization_id: organization_id,
    contact: contact,
    flow: flow
  } do
    replaced = Fixtures.awaiting_flow_context_fixture(%{flow: flow, contact: contact})
    replaced_log = webhook_log_for(organization_id, replaced)

    {:ok, _} = FlowContext.update_flow_context(replaced, %{completed_at: DateTime.utc_now()})

    current = Fixtures.awaiting_flow_context_fixture(%{flow: flow, contact: contact})
    current_log = webhook_log_for(organization_id, current)

    resume(organization_id, contact, flow, replaced_log.id, "stale_answer")

    current_after_stale = Repo.get!(FlowContext, current.id)
    assert current_after_stale.is_await_result
    refute Map.has_key?(current_after_stale.results, "stale_answer")

    resume(organization_id, contact, flow, current_log.id, "answer")

    assert %{"answer" => _} = Repo.get!(FlowContext, current.id).results
  end

  test "a callback whose webhook log has no context resumes the contact's parked context", %{
    organization_id: organization_id,
    contact: contact,
    flow: flow
  } do
    context = Fixtures.awaiting_flow_context_fixture(%{flow: flow, contact: contact})
    webhook_log = Fixtures.webhook_log_fixture(%{organization_id: organization_id})

    resume(organization_id, contact, flow, webhook_log.id, "answer")

    assert %{"answer" => _} = Repo.get!(FlowContext, context.id).results
  end

  defp webhook_log_for(organization_id, context) do
    {:ok, webhook_log} =
      %{organization_id: organization_id, flow_context_id: context.id}
      |> Fixtures.webhook_log_fixture()
      |> WebhookLog.update_webhook_log(%{
        contact_id: context.contact_id,
        flow_id: context.flow_id
      })

    webhook_log
  end

  defp resume(organization_id, contact, flow, webhook_log_id, result_name) do
    Webhook.resume(organization_id, %{"success" => true}, %{
      "contact_id" => contact.id,
      "flow_id" => flow.id,
      "webhook_log_id" => webhook_log_id,
      "result_name" => result_name,
      "success" => true,
      "message" => "callback answer"
    })
  end
end
