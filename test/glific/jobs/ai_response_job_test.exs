defmodule Glific.Jobs.AiResponseJobTest do
  use Glific.DataCase, async: true
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Flows.FlowContext,
    Flows.WebhookLog,
    Jobs.AiResponseJob,
    Messages,
    Repo
  }

  setup do
    organization = Fixtures.get_organization()
    contact = Fixtures.contact_fixture()
    flow = Fixtures.flow_fixture(%{organization_id: organization.id})

    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: contact.id,
        flow_id: flow.id,
        flow_uuid: flow.uuid,
        uuid_map: %{},
        results: %{},
        organization_id: organization.id,
        is_await_result: true
      })

    %{context: context}
  end

  test "schedule_job/2 schedules a job to check for AI response and creates a webhook log", %{context: context} do
    assert {:ok, %Oban.Job{}} = AiResponseJob.schedule_job(context, 60)

    # Check if the job is enqueued
    assert_enqueued(
      worker: AiResponseJob,
      args: %{
        context_id: context.id,
        organization_id: context.organization_id,
        webhook_log_id: fn id -> is_integer(id) end
      }
    )
    
    # Verify webhook log was created
    webhook_log = Repo.one(from wl in WebhookLog, where: wl.method == "AI_RESPONSE_CHECK")
    assert webhook_log != nil
    assert webhook_log.url == "ai_response_timeout"
    assert webhook_log.flow_id == context.flow_id
    assert webhook_log.contact_id == context.contact_id
    assert webhook_log.organization_id == context.organization_id
  end

  test "perform/1 handles a context that no longer exists" do
    # Create webhook log
    {:ok, webhook_log} = WebhookLog.create_webhook_log(%{
      url: "ai_response_timeout",
      method: "AI_RESPONSE_CHECK",
      request_headers: %{},
      organization_id: 1,
      flow_id: 1
    })
    
    job = %Oban.Job{args: %{
      "context_id" => 0, 
      "organization_id" => 1,
      "webhook_log_id" => webhook_log.id
    }}
    
    assert :ok = AiResponseJob.perform(job)
    
    # Check webhook log was updated
    updated_log = Repo.get(WebhookLog, webhook_log.id)
    assert updated_log.status_code == 404
    assert updated_log.error == "Context no longer exists"
  end

  test "perform/1 does nothing if is_await_result is false", %{context: context} do
    # Update context to indicate it's no longer waiting
    {:ok, updated_context} =
      FlowContext.update_flow_context(
        context,
        %{is_await_result: false}
      )

    # Create webhook log
    {:ok, webhook_log} = WebhookLog.create_webhook_log(%{
      url: "ai_response_timeout",
      method: "AI_RESPONSE_CHECK",
      request_headers: %{},
      organization_id: context.organization_id,
      flow_id: context.flow_id,
      contact_id: context.contact_id
    })

    # Create job with updated context
    job = %Oban.Job{args: %{
      "context_id" => updated_context.id, 
      "organization_id" => updated_context.organization_id,
      "webhook_log_id" => webhook_log.id
    }}
    
    # Execute job
    assert :ok = AiResponseJob.perform(job)
    
    # Check that context hasn't changed
    reloaded_context = Repo.get(FlowContext, context.id)
    assert reloaded_context.is_await_result == false
    refute Map.has_key?(reloaded_context.results || %{}, "ai_response_timeout")
    
    # Check webhook log was updated
    updated_log = Repo.get(WebhookLog, webhook_log.id)
    assert updated_log.status_code == 200
    assert updated_log.response_json["status"] == "success"
  end

  test "perform/1 handles a timeout when is_await_result is still true", %{context: context} do
    # Create webhook log
    {:ok, webhook_log} = WebhookLog.create_webhook_log(%{
      url: "ai_response_timeout",
      method: "AI_RESPONSE_CHECK",
      request_headers: %{},
      organization_id: context.organization_id,
      flow_id: context.flow_id,
      contact_id: context.contact_id
    })
    
    # Create job
    job = %Oban.Job{args: %{
      "context_id" => context.id, 
      "organization_id" => context.organization_id,
      "webhook_log_id" => webhook_log.id
    }}
    
    # Execute job
    assert :ok = AiResponseJob.perform(job)
    
    # Check that context has been updated
    reloaded_context = Repo.get(FlowContext, context.id)
    assert reloaded_context.is_await_result == false
    assert Map.has_key?(reloaded_context.results || %{}, "ai_response_timeout")
    assert reloaded_context.results["ai_response_timeout"].success == false
    
    # Check webhook log was updated
    updated_log = Repo.get(WebhookLog, webhook_log.id)
    assert updated_log.status_code == 408
    assert updated_log.error == "Timeout waiting for AI platform response"
  end
end