defmodule Glific.Flows.Webhooks.FilesearchGptTest do
  use GlificWeb.ConnCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  import Glific.WebhookTestHelpers

  alias Glific.{
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
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

    {assistant, _config} = create_assistant_with_config(1)

    {:ok, assistant: assistant}
  end

  defp create_assistant_with_config(organization_id) do
    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{
        name: "Test Filesearch Assistant",
        organization_id: organization_id,
        kaapi_uuid: "kaapi-uuid-filesearch-test",
        assistant_display_id: "asst_test123"
      })
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        version_number: 1,
        kaapi_version_number: 1,
        prompt: "You are a helpful assistant.",
        provider: "openai",
        model: "gpt-4o",
        settings: %{},
        status: :ready,
        organization_id: organization_id
      })
      |> Repo.insert()

    {:ok, assistant} =
      assistant
      |> Assistant.set_active_config_version_changeset(%{
        active_config_version_id: config_version.id
      })
      |> Repo.update()

    {assistant, config_version}
  end

  # Build an action for the filesearch-gpt webhook
  defp build_filesearch_action(assistant_display_id) do
    %Action{
      type: "call_webhook",
      method: "FUNCTION",
      url: "filesearch-gpt",
      headers: %{"Content-Type" => "application/json"},
      body:
        Jason.encode!(%{
          question: "What is Glific?",
          assistant_id: assistant_display_id
        }),
      result_name: "filesearch"
    }
  end

  describe "filesearch-gpt" do
    test "happy path - flow moves to success route after callback", %{
      conn: %{assigns: %{organization_id: org_id}} = conn,
      assistant: assistant
    } do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{success: true}
          }
      end)

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
          node_uuid: node.uuid
        })

      context = Repo.preload(context, [:contact, :flow])

      action = build_filesearch_action(assistant.assistant_display_id)

      assert {:wait, _parked, []} = Action.execute(action, context, [])
      Oban.drain_queue(queue: :gpt_webhook_queue)

      # The webhook log is created in do_oban — fetch the latest one
      webhook_logs = WebhookLog.list_webhook_logs(%{filter: %{organization_id: org_id}})
      webhook_log = List.first(webhook_logs)
      assert webhook_log != nil

      expected_message = "Glific is an open-source messaging platform"

      params =
        build_unified_callback_params(
          org_id,
          flow.id,
          contact.id,
          webhook_log.id,
          true,
          expected_message
        )

      conn = post(conn, "/webhook/flow_resume", params)
      assert json_response(conn, 200) == ""

      message = await_flow_message(contact.id, expected_message)
      assert message.body == expected_message
    end

    test "failure callback - flow moves to failure route", %{
      conn: %{assigns: %{organization_id: org_id}} = conn,
      assistant: assistant
    } do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{success: true}
          }
      end)

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
          node_uuid: node.uuid
        })

      context = Repo.preload(context, [:contact, :flow])

      action = build_filesearch_action(assistant.assistant_display_id)

      assert {:wait, _parked, []} = Action.execute(action, context, [])
      Oban.drain_queue(queue: :gpt_webhook_queue)

      # Fetch the webhook log created in do_oban
      webhook_logs = WebhookLog.list_webhook_logs(%{filter: %{organization_id: org_id}})
      webhook_log = List.first(webhook_logs)
      assert webhook_log != nil

      params =
        build_unified_callback_params(
          org_id,
          flow.id,
          contact.id,
          webhook_log.id,
          false,
          "Kaapi filesearch failed"
        )

      conn = post(conn, "/webhook/flow_resume", params)
      assert json_response(conn, 200) == ""

      message = await_flow_message(contact.id, "failure")
      assert message.body == "failure"
    end

    test "timeout - outbound Kaapi request times out, WebhookLog records error", %{
      conn: %{assigns: %{organization_id: org_id}} = _conn,
      assistant: assistant
    } do
      Tesla.Mock.mock(fn _ -> {:error, :timeout} end)

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
          wakeup_at: DateTime.add(DateTime.utc_now(), 60),
          is_await_result: true,
          node_uuid: node.uuid
        })

      context = Repo.preload(context, [:contact, :flow])

      flow_filter = %{
        flow_id: flow.id,
        contact_id: contact.id,
        organization_id: org_id
      }

      action = %Action{
        method: "FUNCTION",
        url: "filesearch-gpt",
        headers: %{"Content-Type" => "application/json"},
        body:
          Jason.encode!(%{
            question: "What is Glific?",
            assistant_id: assistant.assistant_display_id
          }),
        result_name: "filesearch"
      }

      assert Webhook.execute(action, context) == nil

      [job | _] = all_enqueued(worker: Webhook, prefix: "global")
      assert job.queue == "gpt_webhook_queue"

      Oban.drain_queue(queue: :gpt_webhook_queue)

      # The worker dispatches FilesearchGpt.call, the Kaapi request times out, and the
      # call returns %{success: false}, so the webhook log records the failure.
      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_filter}))
      assert log != nil
      assert log.error != nil
    end
  end
end
