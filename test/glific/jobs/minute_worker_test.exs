defmodule Glific.Jobs.MinuteWorkerTest do
  use Glific.DataCase, async: true
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Flows.FlowContext,
    Flows.WebhookLog,
    Jobs.MinuteWorker,
    Repo
  }

  describe "check_stale_ai_responses/0" do
    setup do
      organization = Fixtures.get_organization()
      contact = Fixtures.contact_fixture()
      flow = Fixtures.flow_fixture(%{organization_id: organization.id})

      {:ok, fresh_context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          results: %{},
          organization_id: organization.id,
          is_await_result: true
        })

      # Create a stale context that was inserted 10 minutes ago
      stale_time = DateTime.utc_now() |> DateTime.add(-10 * 60, :second)

      {:ok, stale_context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          results: %{},
          organization_id: organization.id,
          is_await_result: true
        })

      # Manually update the inserted_at and updated_at fields
      # to simulate a stale context
      Repo.update_all(
        from(fc in FlowContext, where: fc.id == ^stale_context.id),
        set: [inserted_at: stale_time, updated_at: stale_time]
      )

      stale_context = Repo.get(FlowContext, stale_context.id)

      %{fresh_context: fresh_context, stale_context: stale_context}
    end

    test "schedules jobs for stale contexts but not fresh ones", %{
      fresh_context: fresh_context,
      stale_context: stale_context
    } do
      # Clear all previously enqueued jobs
      Oban.Testing.with_testing_mode(:manual, fn ->
        # Call the function directly
        assert :ok = MinuteWorker.perform(%Oban.Job{args: %{"job" => "check_stale_ai_responses"}})

        # The job should be scheduled only for stale contexts
        assert_enqueued(
          worker: Glific.Jobs.AiResponseJob,
          args: %{
            context_id: stale_context.id,
            organization_id: stale_context.organization_id,
            webhook_log_id: fn id -> is_integer(id) end
          }
        )

        # Verify webhook log was created
        webhook_log = Repo.one(from wl in WebhookLog, 
          where: wl.method == "AI_RESPONSE_CHECK" and 
                 wl.url == "stale_ai_response_check" and
                 wl.flow_id == ^stale_context.flow_id)
        assert webhook_log != nil

        # No job should be scheduled for fresh contexts
        refute_enqueued(
          worker: Glific.Jobs.AiResponseJob,
          args: %{
            context_id: fresh_context.id,
            organization_id: fresh_context.organization_id
          }
        )
      end)
    end

    test "doesn't schedule jobs for contexts where is_await_result is false", %{stale_context: stale_context} do
      # Update the context to set is_await_result to false
      {:ok, updated_context} =
        FlowContext.update_flow_context(
          stale_context,
          %{is_await_result: false}
        )

      # Clear all previously enqueued jobs
      Oban.Testing.with_testing_mode(:manual, fn ->
        # Call the function directly
        assert :ok = MinuteWorker.perform(%Oban.Job{args: %{"job" => "check_stale_ai_responses"}})

        # No job should be scheduled
        refute_enqueued(
          worker: Glific.Jobs.AiResponseJob,
          args: %{
            context_id: updated_context.id,
            organization_id: updated_context.organization_id
          }
        )
      end)
    end
  end
end