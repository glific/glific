defmodule Glific.Flows.Webhooks.CallAndWaitTest do
  use GlificWeb.ConnCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Flows.Action,
    Flows.Flow,
    Flows.FlowContext,
    Flows.Webhook,
    Flows.WebhookLog,
    Partners,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    SeedsDev.seed_organizations()

    {:ok, _credential} =
      Partners.create_credential(%{
        organization_id: 1,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{"api_key" => "sk_test_key"},
        is_active: true
      })

    Partners.get_organization!(1) |> Partners.fill_cache()
    :ok
  end

  # Build a flow context parked in await state at the first node of the
  # `call_and_wait` flow. This mirrors the setup in flow_resume_controller_test.exs.
  defp build_await_context(organization_id) do
    contact = Fixtures.contact_fixture(%{organization_id: organization_id})
    webhook_log = Fixtures.webhook_log_fixture(%{organization_id: organization_id})
    flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})
    [node | _] = flow.nodes

    {:ok, _context} =
      FlowContext.create_flow_context(%{
        contact_id: contact.id,
        flow_id: flow.id,
        flow_uuid: flow.uuid,
        uuid_map: %{},
        organization_id: organization_id,
        wakeup_at: DateTime.add(DateTime.utc_now(), 60),
        is_await_result: true,
        node_uuid: node.uuid
      })

    {contact, webhook_log, flow}
  end

  # Build callback params in the OLD Kaapi Responses API format:
  # data.message, data.contact_id, data.flow_id, etc. (not data.response.output)
  defp build_old_format_callback_params(
         organization_id,
         flow_id,
         contact_id,
         webhook_log_id,
         success,
         message
       ) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    signature_payload = %{
      "organization_id" => organization_id,
      "flow_id" => flow_id,
      "contact_id" => contact_id,
      "timestamp" => timestamp
    }

    signature =
      Glific.signature(
        organization_id,
        Jason.encode!(signature_payload),
        timestamp
      )

    %{
      "data" => %{
        "callback" =>
          "https://api.glific.com/webhook/flow_resume?organization_id=#{organization_id}",
        "contact_id" => contact_id,
        "flow_id" => flow_id,
        "message" => message,
        "organization_id" => organization_id,
        "response_id" => "resp_#{:rand.uniform(100_000)}",
        "signature" => signature,
        "status" => if(success, do: "success", else: "failure"),
        "timestamp" => timestamp,
        "webhook_log_id" => webhook_log_id,
        "result_name" => "filesearch"
      },
      "success" => success
    }
  end

  describe "call_and_wait" do
    test "happy path - flow resumes with AI response on success callback", %{
      conn: %{assigns: %{organization_id: org_id}} = conn
    } do
      {contact, webhook_log, flow} = build_await_context(org_id)

      params =
        build_old_format_callback_params(
          org_id,
          flow.id,
          contact.id,
          webhook_log.id,
          true,
          "AI response from Kaapi assistant"
        )

      conn = post(conn, "/webhook/flow_resume", params)
      assert json_response(conn, 200) == ""

      message = await_flow_message(contact.id, "AI response from Kaapi assistant")
      assert message.body == "AI response from Kaapi assistant"
    end

    test "failure callback - flow routes to failure branch", %{
      conn: %{assigns: %{organization_id: org_id}} = conn
    } do
      {contact, webhook_log, flow} = build_await_context(org_id)

      params =
        build_old_format_callback_params(
          org_id,
          flow.id,
          contact.id,
          webhook_log.id,
          false,
          "Kaapi error: response generation failed"
        )

      conn = post(conn, "/webhook/flow_resume", params)
      assert json_response(conn, 200) == ""

      message = await_flow_message(contact.id, "failure")
      assert message.body == "failure"

      updated_log = Repo.get!(WebhookLog, webhook_log.id)
      assert updated_log.response_json["message"] == "Kaapi error: response generation failed"
      assert updated_log.response_json["success"] == false
    end

    test "timeout - outbound Kaapi request times out, webhook log records error", %{
      conn: %{assigns: %{organization_id: org_id}} = _conn
    } do
      Tesla.Mock.mock(fn _ -> {:error, :timeout} end)

      contact = Fixtures.contact_fixture(%{organization_id: org_id})

      flow_attrs = %{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: contact.id,
        organization_id: org_id
      }

      {:ok, context} = FlowContext.create_flow_context(flow_attrs)
      context = Repo.preload(context, [:contact, :flow])

      action = %Action{
        method: "FUNCTION",
        url: "call_and_wait",
        headers: %{"X-API-KEY" => "sk_test_key", "Content-Type" => "application/json"},
        body:
          Jason.encode!(%{
            question: "test question",
            flow_id: 1,
            contact_id: contact.id,
            organization_id: org_id,
            result_name: "response",
            webhook_log_id: 1
          })
      }

      assert Webhook.execute(action, context) == nil

      [job | _] = all_enqueued(worker: Webhook, prefix: "global")
      assert job.queue == "gpt_webhook_queue"

      Oban.drain_queue(queue: :gpt_webhook_queue)

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log != nil
      assert log.error != nil
    end
  end

  @await_attempts 50
  @await_interval_ms 100

  defp await_flow_message(contact_id, expected_body) do
    await_flow_resume_tasks()
    await_flow_message(contact_id, expected_body, @await_attempts)
  end

  defp await_flow_resume_tasks(attempts \\ 50)
  defp await_flow_resume_tasks(0), do: flunk("Timed out waiting for flow resume task")

  defp await_flow_resume_tasks(attempts) do
    case Supervisor.count_children(Glific.TaskSupervisor) do
      %{active: 0} ->
        :ok

      _ ->
        Process.sleep(@await_interval_ms)
        await_flow_resume_tasks(attempts - 1)
    end
  end

  defp await_flow_message(contact_id, expected_body, 0) do
    flunk("Timed out waiting for message #{inspect(expected_body)} for contact #{contact_id}")
  end

  defp await_flow_message(contact_id, expected_body, attempts) do
    case Glific.Messages.list_messages(%{
           filter: %{contact_id: contact_id},
           opts: %{limit: 1, order: :desc}
         }) do
      [%{body: ^expected_body} = msg | _] ->
        msg

      _ ->
        Process.sleep(@await_interval_ms)
        await_flow_message(contact_id, expected_body, attempts - 1)
    end
  end
end
