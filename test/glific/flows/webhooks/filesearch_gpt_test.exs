defmodule Glific.Flows.Webhooks.FilesearchGptTest do
  use GlificWeb.ConnCase, async: false

  import Ecto.Query
  import Mock
  import Glific.WebhookTestHelpers

  alias Glific.{
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Fixtures,
    Flows.Action,
    Flows.Flow,
    Flows.FlowContext,
    Flows.WebhookLog,
    Partners,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    SeedsDev.seed_organizations()
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

  defp enable_kaapi(organization_id) do
    {:ok, credential} =
      Partners.create_credential(%{
        organization_id: organization_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{"api_key" => "sk_test_key"}
      })

    Partners.update_credential(credential, %{
      keys: %{},
      secrets: %{"api_key" => "sk_test_key"},
      is_active: true,
      organization_id: organization_id,
      shortcode: "kaapi"
    })
  end

  describe "filesearch-gpt" do
    test "happy path - flow moves to success route after callback", %{
      conn: %{assigns: %{organization_id: org_id}} = conn,
      assistant: assistant
    } do
      enable_kaapi(org_id)

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

      assert {:wait, _context, []} = Action.execute(action, context, [])

      webhook_logs = WebhookLog.list_webhook_logs(%{filter: %{organization_id: org_id}})
      webhook_log = List.first(webhook_logs)
      assert webhook_log != nil

      expected_message = "Glific is an open-source messaging platform"

      params =
        build_old_format_callback_params(
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
      enable_kaapi(org_id)

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

      assert {:wait, _context, []} = Action.execute(action, context, [])

      webhook_logs = WebhookLog.list_webhook_logs(%{filter: %{organization_id: org_id}})
      webhook_log = List.first(webhook_logs)
      assert webhook_log != nil

      params =
        build_old_format_callback_params(
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
      enable_kaapi(org_id)

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
          node_uuid: node.uuid
        })

      context = Repo.preload(context, [:contact, :flow])

      action = build_filesearch_action(assistant.assistant_display_id)

      result = Action.execute(action, context, [])
      assert match?({:ok, _, _}, result)

      flow_filter = %{
        flow_id: flow.id,
        contact_id: contact.id,
        organization_id: org_id
      }

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_filter}))
      assert log != nil
      assert log.error != nil
    end
  end

  describe "FileSearch-GPT credential handling" do
    test "wakeup_one/1 resumes a contact's waiting flow context and clears wakeup_at",
         %{organization_id: organization_id} do
      enable_kaapi(organization_id)

      contact = Fixtures.contact_fixture()
      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "wait_for_result"})
      [node | _tail] = flow.nodes

      {:ok, context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          organization_id: organization_id,
          node_uuid: node.uuid
        })

      assert {:ok, _context, []} = FlowContext.wakeup_one(context)

      context = Repo.get!(FlowContext, context.id)
      assert context.wakeup_at == nil
      assert context.is_background_flow == false
    end

    test "logs descriptive error when kaapi is not active", %{conn: conn} do
      organization_id = conn.assigns.organization_id

      contact = Fixtures.contact_fixture()

      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})

      [node | _tail] = flow.nodes

      {:ok, context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          organization_id: organization_id,
          node_uuid: node.uuid
        })

      context = Repo.preload(context, [:flow, :contact])

      action = %Action{
        type: "call_webhook",
        uuid: "UUID 1",
        url: "filesearch-gpt",
        body:
          "{\n\"question\": \"tell me a fact about consistency\",\n  \"flow_id\": \"@flow.id\",\n  " <>
            "\"endpoint\": \"This is not a secret/api/v1/responses\",\n  " <>
            "\"contact_id\": \"@contact.id\",\n  \"callback_url\": \"https://91e372283c55/webhook/flow_resume\",\n  " <>
            "\"assistant_id\": \"asst_pJxxD\"\n}",
        method: "FUNCTION",
        headers: %{
          Accept: "application/json",
          "Content-Type": "application/json"
        },
        result_name: "filesearch",
        node_uuid: "Test UUID"
      }

      assert {:ok, flow_context, [message]} = Action.execute(action, context, [])

      webhook_log =
        WebhookLog
        |> where(url: "filesearch-gpt")
        |> order_by(desc: :inserted_at)
        |> limit(1)
        |> Repo.one()

      assert webhook_log.error == "Kaapi is not active"

      assert message.body == "Failure"
      assert flow_context.id == context.id
    end

    test "reports SystemError and fails the flow when Kaapi is not active",
         %{conn: conn} do
      organization_id = conn.assigns.organization_id

      contact = Fixtures.contact_fixture()

      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})

      [node | _tail] = flow.nodes

      {:ok, context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          organization_id: organization_id,
          node_uuid: node.uuid
        })

      context = Repo.preload(context, [:flow, :contact])

      action = %Action{
        type: "call_webhook",
        uuid: "UUID 1",
        url: "filesearch-gpt",
        body:
          "{\n\"question\": \"tell me a fact\",\n  \"flow_id\": \"@flow.id\",\n  " <>
            "\"contact_id\": \"@contact.id\",\n  \"assistant_id\": \"asst_pJxxD\"\n}",
        method: "FUNCTION",
        headers: %{
          Accept: "application/json",
          "Content-Type": "application/json"
        },
        result_name: "filesearch",
        node_uuid: "Test UUID"
      }

      test_pid = self()

      # report_to_appsignal/2 is a local call inside Webhook, so we intercept at the
      # Appsignal boundary rather than mocking Webhook itself (local calls bypass mocks).
      with_mock Elixir.Appsignal, [:passthrough],
        send_error: fn exception, _stack, _configurator ->
          send(test_pid, {:appsignal_error, exception})
          :ok
        end do
        Action.execute(action, context, [])
      end

      webhook_log = Repo.get_by(WebhookLog, %{url: "filesearch-gpt"})
      assert webhook_log.error == "Kaapi is not active"
      assert webhook_log.status_code == 400

      assert_received {:appsignal_error, %Glific.Flows.Webhook.SystemError{} = exception}
      assert Exception.message(exception) == "Webhook system_error: Kaapi is not active"
    end
  end

  @kaapi_response "Glific is an open-source, two-way messaging platform designed for nonprofits to scale their outreach via WhatsApp. It helps organizations automate conversations, manage contacts, and measure impact, all in one centralized tool"

  describe "FileSearch-GPT via the Unified API" do
    test "executes unified API filesearch routing to /api/v1/llm/call",
         %{conn: conn} do
      organization_id = conn.assigns.organization_id

      enable_kaapi(organization_id)

      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Test Unified Assistant",
          organization_id: organization_id,
          kaapi_uuid: "kaapi-uuid-test-123",
          assistant_display_id: "asst_pJxxD"
        })
        |> Repo.insert()

      {:ok, config_version} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          version_number: 3,
          kaapi_version_number: 1,
          prompt: "You are a helpful assistant.",
          provider: "openai",
          model: "gpt-4o",
          settings: %{},
          status: :ready,
          organization_id: organization_id
        })
        |> Repo.insert()

      {:ok, _assistant} =
        assistant
        |> Assistant.set_active_config_version_changeset(%{
          active_config_version_id: config_version.id
        })
        |> Repo.update()

      contact = Fixtures.contact_fixture()

      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})

      [node | _tail] = flow.nodes

      {:ok, context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          organization_id: organization_id,
          node_uuid: node.uuid
        })

      context = Repo.preload(context, [:flow, :contact])

      action = %Action{
        type: "call_webhook",
        uuid: "UUID 1",
        url: "filesearch-gpt",
        body:
          "{\n\"question\": \"tell me about glific\",\n  \"flow_id\": \"@flow.id\",\n  " <>
            "\"contact_id\": \"@contact.id\",\n  \"assistant_id\": \"asst_pJxxD\"\n}",
        method: "FUNCTION",
        headers: %{
          Accept: "application/json",
          "Content-Type": "application/json"
        },
        result_name: "filesearch",
        node_uuid: "Test UUID"
      }

      Tesla.Mock.mock(fn
        %Tesla.Env{method: :post, url: url} ->
          assert String.contains?(url, "/api/v1/llm/call")

          %Tesla.Env{
            status: 200,
            body: %{
              error: nil,
              data: %{
                message: "LLM call started",
                status: "processing",
                success: true
              }
            }
          }
      end)

      assert {:wait, _context, []} = Action.execute(action, context, [])

      webhook_log = Repo.get_by(WebhookLog, %{url: "filesearch-gpt"})
      assert webhook_log != nil

      timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

      signature_payload = %{
        "organization_id" => organization_id,
        "flow_id" => flow.id,
        "contact_id" => contact.id,
        "timestamp" => timestamp
      }

      signature =
        Glific.signature(
          organization_id,
          Jason.encode!(signature_payload),
          signature_payload["timestamp"]
        )

      callback_params = %{
        "data" => %{
          "contact_id" => contact.id,
          "flow_id" => flow.id,
          "organization_id" => organization_id,
          "signature" => signature,
          "timestamp" => timestamp,
          "webhook_log_id" => webhook_log.id,
          "result_name" => "filesearch",
          "message" => @kaapi_response,
          "response_id" => "resp_unified_test_123",
          "status" => "success"
        },
        "success" => true
      }

      conn = post(conn, "/webhook/flow_resume", callback_params)
      assert json_response(conn, 200) == ""

      message = await_flow_message(contact.id, @kaapi_response)
      assert message.body == @kaapi_response
    end
  end
end
