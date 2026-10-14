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
    Flows.LlmCall,
    Flows.Webhook,
    Flows.WebhookLog,
    Flows.Webhooks.FilesearchGpt,
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

  describe "filesearch-gpt callback records the LLM call" do
    setup %{conn: %{assigns: %{organization_id: organization_id}}, assistant: assistant} do
      Tesla.Mock.mock(fn %{method: :post} -> %Tesla.Env{status: 200, body: %{success: true}} end)

      contact = Fixtures.contact_fixture(%{organization_id: organization_id})
      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})
      [node | _] = flow.nodes

      {:ok, context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          organization_id: organization_id,
          node_uuid: node.uuid
        })

      context = Repo.preload(context, [:contact, :flow])
      action = build_filesearch_action(assistant.assistant_display_id)

      assert {:wait, _parked, []} = Action.execute(action, context, [])
      Oban.drain_queue(queue: :gpt_webhook_queue)

      [webhook_log | _] =
        WebhookLog.list_webhook_logs(%{filter: %{organization_id: organization_id}})

      %{contact: contact, flow: flow, webhook_log: webhook_log}
    end

    test "with input and output guardrails", %{conn: conn} = setup_context do
      conn =
        post(
          conn,
          "/webhook/flow_resume",
          signed_callback(:with_input_and_output_guardrail, setup_context)
        )

      assert json_response(conn, 200) == ""

      llm_call = await_llm_call(setup_context.contact.id)
      assert llm_call.flow_id == setup_context.flow.id
      assert llm_call.success

      assert llm_call.provider_response_id ==
               "resp_0ac70facbc55fd98006acdc4f7e8b487d2808cf2a7ccfa1d97"

      assert llm_call.model == "gpt-5.4-mini-2026-03-17"
      assert llm_call.input_from_user == "call me kutta at 8979220110 from Ram village"
      assert llm_call.input_to_llm == "call me [REDACTED_SLUR] at <phone_number> from <location>"

      assert llm_call.output_from_llm ==
               "Hello! I can’t help use hateful slurs or place a call for you. If you want, I can help you write a polite text or phone script instead."

      assert llm_call.output_to_user == llm_call.output_from_llm
      assert length(llm_call.input_guardrail) == 2
      assert length(llm_call.output_guardrail) == 1
      assert llm_call.tokens["total_tokens"] == 485
    end

    test "without guardrails falls back to the question the node sent",
         %{conn: conn} = setup_context do
      conn =
        post(conn, "/webhook/flow_resume", signed_callback(:without_guardrail, setup_context))

      assert json_response(conn, 200) == ""

      llm_call = await_llm_call(setup_context.contact.id)
      assert llm_call.input_from_user == "What is Glific?"
      assert llm_call.input_to_llm == "What is Glific?"
      assert llm_call.output_to_user =~ "I’m not sure what you’d like to know"
      assert llm_call.input_guardrail == nil
      assert llm_call.output_guardrail == nil
      assert llm_call.tokens["total_tokens"] == 384
    end
  end

  defp signed_callback(sample, %{contact: contact, flow: flow, webhook_log: webhook_log}) do
    %{"metadata" => request_metadata} =
      build_unified_callback_params(
        webhook_log.organization_id,
        flow.id,
        contact.id,
        webhook_log.id,
        true,
        "",
        %{"call_type" => "llm", "webhook_name" => "filesearch-gpt"}
      )

    sample
    |> kaapi_llm_callback()
    |> Map.update!("metadata", &Map.merge(&1, request_metadata))
  end

  # The callback is processed in a supervised task, so poll for the row.
  defp await_llm_call(contact_id, attempts \\ 50)
  defp await_llm_call(_contact_id, 0), do: flunk("Timed out waiting for the LLM call row")

  defp await_llm_call(contact_id, attempts) do
    case Repo.get_by(LlmCall, contact_id: contact_id) do
      nil ->
        Process.sleep(100)
        await_llm_call(contact_id, attempts - 1)

      llm_call ->
        llm_call
    end
  end

  # Dispatch-level tests: exercise call/2's lookup_kaapi_config validation branches and Kaapi
  # failure shaping directly (the e2e tests above only cover the happy/failure-callback/timeout
  # flow paths).
  defp lookup_fields(assistant_id) do
    %{
      "assistant_id" => assistant_id,
      "question" => "test",
      "organization_id" => "1",
      "flow_id" => "1",
      "contact_id" => "2",
      "webhook_log_id" => 1,
      "result_name" => "response"
    }
  end

  describe "filesearch-gpt dispatch — lookup_kaapi_config" do
    test "returns error when assistant_id is nil" do
      assert {:error, :invalid_input, "assistant_id is required"} =
               FilesearchGpt.call(Map.delete(lookup_fields("x"), "assistant_id"), %{})
    end

    test "returns error when assistant not found" do
      assert {:error, :invalid_input, reason} =
               FilesearchGpt.call(lookup_fields("nonexistent_id"), %{})

      assert reason =~ "Assistant not found"
    end

    test "returns error when kaapi_version_number is nil" do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Version Nil Test",
          organization_id: 1,
          kaapi_uuid: "kaapi_uuid_test"
        })
        |> Repo.insert()

      {:ok, config} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: 1,
          provider: "openai",
          model: "gpt-4o",
          prompt: "test",
          settings: %{},
          status: :ready,
          kaapi_version_number: nil
        })
        |> Repo.insert()

      {:ok, assistant} =
        assistant
        |> Assistant.set_active_config_version_changeset(%{active_config_version_id: config.id})
        |> Repo.update()

      assert {:error, :invalid_input, reason} =
               FilesearchGpt.call(lookup_fields(assistant.assistant_display_id), %{})

      assert reason =~ "Kaapi version number not found"
    end

    test "returns error when kaapi_uuid is nil" do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{name: "No UUID Test", organization_id: 1})
        |> Repo.insert()

      {:ok, config} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: 1,
          provider: "openai",
          model: "gpt-4o",
          prompt: "test",
          settings: %{},
          status: :ready
        })
        |> Repo.insert()

      {:ok, assistant} =
        assistant
        |> Assistant.set_active_config_version_changeset(%{active_config_version_id: config.id})
        |> Repo.update()

      assert {:error, :invalid_input, reason} =
               FilesearchGpt.call(lookup_fields(assistant.assistant_display_id), %{})

      assert reason =~ "Assistant is still being set up"
    end

    test "returns :invalid_input when no active config version is linked" do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "No Active Config",
          organization_id: 1,
          kaapi_uuid: "kaapi_uuid_present"
        })
        |> Repo.insert()

      assert {:error, :invalid_input, reason} =
               FilesearchGpt.call(lookup_fields(assistant.assistant_display_id), %{})

      assert reason =~ "No active config version"
    end
  end

  describe "filesearch-gpt dispatch — guardrail metadata" do
    setup do
      test_pid = self()

      Tesla.Mock.mock(fn %{method: :post} = env ->
        send(test_pid, {:llm_request_body, Jason.decode!(env.body)})
        %Tesla.Env{status: 200, body: %{"success" => true}}
      end)

      :ok
    end

    test "asks Kaapi for guardrail metadata when the flag is enabled", %{assistant: assistant} do
      FunWithFlags.enable(:is_ai_guardrail_enabled, for_actor: %{organization_id: 1})

      FilesearchGpt.call(lookup_fields(assistant.assistant_display_id), %{})

      assert_receive {:llm_request_body, %{"include_guardrail_metadata" => true}}
    end

    test "does not ask for guardrail metadata when the flag is disabled", %{assistant: assistant} do
      FunWithFlags.disable(:is_ai_guardrail_enabled, for_actor: %{organization_id: 1})

      FilesearchGpt.call(lookup_fields(assistant.assistant_display_id), %{})

      assert_receive {:llm_request_body, %{"include_guardrail_metadata" => false}}
    end
  end

  describe "filesearch-gpt dispatch — Kaapi failure result" do
    test "returns failure result on a Kaapi 4xx response", %{assistant: assistant} do
      Tesla.Mock.mock(fn
        %{method: :post} -> %Tesla.Env{status: 400, body: %{"error" => "bad request"}}
      end)

      # A dispatch-phase Kaapi HTTP failure is system (the callback classifier, not dispatch,
      # is what maps a real provider 4xx to config).
      assert {:error, :unknown, _reason} =
               FilesearchGpt.call(lookup_fields(assistant.assistant_display_id), %{})
    end

    test "returns failure result on a Kaapi 5xx response", %{assistant: assistant} do
      Tesla.Mock.mock(fn
        %{method: :post} -> %Tesla.Env{status: 503, body: %{}}
      end)

      assert {:error, :unknown, _reason} =
               FilesearchGpt.call(lookup_fields(assistant.assistant_display_id), %{})
    end

    test "returns :unknown on a Kaapi transport error", %{assistant: assistant} do
      Tesla.Mock.mock(fn %{method: :post} -> {:error, :econnrefused} end)

      assert {:error, :unknown, _reason} =
               FilesearchGpt.call(lookup_fields(assistant.assistant_display_id), %{})
    end

    test "returns failure result when Kaapi returns 200 with a success:false body", %{
      assistant: assistant
    } do
      Tesla.Mock.mock(fn
        %{method: :post} -> %Tesla.Env{status: 200, body: %{success: false, message: "boom"}}
      end)

      # error_type "kaapi_logical_failure" is a raw string, not a known ErrorType.t() atom, so
      # to_result/1 fails it safe to :unknown; http_status is folded into the reason.
      assert {:error, :unknown, "boom (HTTP 200)"} =
               FilesearchGpt.call(lookup_fields(assistant.assistant_display_id), %{})
    end
  end
end
