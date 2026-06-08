defmodule Glific.Flows.Webhooks.FilesearchGptTest do
  use GlificWeb.ConnCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

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

    Partners.get_organization!(1) |> Partners.fill_cache()

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

  # Build the callback params for /webhook/flow_resume
  defp build_callback_params(
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
        "signature" => signature,
        "status" => if(success, do: "success", else: "failure"),
        "timestamp" => timestamp,
        "webhook_log_id" => webhook_log_id,
        "result_name" => "filesearch"
      },
      "success" => success
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

      Webhook.execute_unified_filesearch(action, context)

      # The webhook log is created inside execute_unified_filesearch — fetch the latest one
      webhook_logs = WebhookLog.list_webhook_logs(%{filter: %{organization_id: org_id}})
      webhook_log = List.first(webhook_logs)
      assert webhook_log != nil

      expected_message = "Glific is an open-source messaging platform"

      params =
        build_callback_params(
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

      Webhook.execute_unified_filesearch(action, context)

      # Fetch the webhook log created inside execute_unified_filesearch
      webhook_logs = WebhookLog.list_webhook_logs(%{filter: %{organization_id: org_id}})
      webhook_log = List.first(webhook_logs)
      assert webhook_log != nil

      params =
        build_callback_params(
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

    test "timeout - outbound Kaapi request times out, webhook log records error", %{
      conn: %{assigns: %{organization_id: org_id}} = _conn,
      assistant: assistant
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

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log != nil
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
