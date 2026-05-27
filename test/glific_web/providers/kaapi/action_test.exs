defmodule GlificWeb.Providers.Kaapi.ActionTest do
  use GlificWeb.ConnCase
  import Ecto.Query
  import Mock

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

    :ok
  end

  @kaapi_response "Glific is an open-source, two-way messaging platform designed for nonprofits to scale their outreach via WhatsApp. It helps organizations automate conversations, manage contacts, and measure impact, all in one centralized tool"

  describe "Call a webhook for FileSearch-GPT (Kaapi credential handling)" do
    test "wakeup_one/1 resumes a contact's waiting flow context and clears wakeup_at",
         %{organization_id: organization_id} = _attrs do
      # activate kaapi
      enable_kaapi(%{organization_id: organization_id})

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

      flow =
        Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})

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
          "{\n\"question\": \"tell me a fact about consistency\",\n  \"flow_id\": \"@flow.id\",\n  \"endpoint\": \"This is not a secretapi/v1/responses\",\n
          \"contact_id\": \"@contact.id\",\n  \"callback_url\": \"https://91e372283c55/webhook/flow_resume\",\n  \"assistant_id\": \"asst_pJxxD\"\n}",
        method: "FUNCTION",
        headers: %{
          Accept: "application/json",
          "Content-Type": "application/json"
        },
        result_name: "filesearch",
        node_uuid: "Test UUID"
      }

      message_stream = []

      assert {:ok, flow_context, [message]} = Action.execute(action, context, message_stream)

      webhook_log =
        WebhookLog
        |> where(url: "filesearch-gpt")
        |> order_by(desc: :inserted_at)
        |> limit(1)
        |> Repo.one()

      assert webhook_log.error ==
               "Kaapi is not active"

      # It should go to the failure category and send the failure message,
      # since the node in the failure category has the failure message as its body.
      assert message.body == "Failure"
      assert flow_context.id == context.id
    end

    test "reports SystemError and fails the flow when Kaapi is not active",
         %{conn: conn} do
      organization_id = conn.assigns.organization_id

      contact = Fixtures.contact_fixture()

      flow =
        Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})

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
          "{\n\"question\": \"tell me a fact\",\n  \"flow_id\": \"@flow.id\",\n  \"contact_id\": \"@contact.id\",\n  \"assistant_id\": \"asst_pJxxD\"\n}",
        method: "FUNCTION",
        headers: %{
          Accept: "application/json",
          "Content-Type": "application/json"
        },
        result_name: "filesearch",
        node_uuid: "Test UUID"
      }

      test_pid = self()

      with_mock Appsignal, [:passthrough],
        send_error: fn exception, _stack, _configurator ->
          send(test_pid, {:appsignal_error, exception})
          :ok
        end do
        Action.execute(action, context, [])
      end

      # fail + log: the webhook log records "Kaapi is not active"
      webhook_log = Repo.get_by(WebhookLog, %{url: "filesearch-gpt"})
      assert webhook_log.error == "Kaapi is not active"
      assert webhook_log.status_code == 400

      # report: a SystemError is sent to AppSignal
      assert_received {:appsignal_error, %Glific.Flows.Webhook.SystemError{} = exception}
      assert Exception.message(exception) == "Webhook system_error: Kaapi is not active"
    end
  end

  describe "Call a webhook for FileSearch-GPT via the Unified API" do
    test "executes unified API filesearch routing to /api/v1/llm/call",
         %{conn: conn} do
      organization_id = conn.assigns.organization_id

      # activate kaapi
      enable_kaapi(%{organization_id: organization_id})

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

      assistant
      |> Assistant.set_active_config_version_changeset(%{
        active_config_version_id: config_version.id
      })
      |> Repo.update()

      contact = Fixtures.contact_fixture()

      flow =
        Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})

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
          "{\n\"question\": \"tell me about glific\",\n  \"flow_id\": \"@flow.id\",\n  \"contact_id\": \"@contact.id\",\n  \"assistant_id\": \"asst_pJxxD\"\n}",
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
          # Verify it hits the unified API endpoint
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

      message_stream = []

      # Execute the webhook node — should use unified API path
      assert {:wait, _context, []} = Action.execute(action, context, message_stream)

      # Verify webhook log was created
      webhook_log = Repo.get_by(WebhookLog, %{url: "filesearch-gpt"})
      assert webhook_log != nil

      # Simulate callback from Kaapi and verify flow resumes
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

      conn =
        conn
        |> post("/webhook/flow_resume", callback_params)

      assert json_response(conn, 200) == ""

      message = await_flow_message(contact.id, @kaapi_response)
      assert message.body == @kaapi_response
    end
  end

  @await_flow_message_attempts 50
  @await_flow_message_interval_ms 100

  defp await_flow_message(contact_id, expected_body) do
    await_flow_resume_tasks()
    await_flow_message(contact_id, expected_body, @await_flow_message_attempts)
  end

  defp await_flow_resume_tasks(attempts \\ 50)

  defp await_flow_resume_tasks(0) do
    flunk("Timed out waiting for flow resume background task")
  end

  defp await_flow_resume_tasks(attempts) do
    case Supervisor.count_children(Glific.TaskSupervisor) do
      %{active: 0} ->
        :ok

      _ ->
        Process.sleep(@await_flow_message_interval_ms)
        await_flow_resume_tasks(attempts - 1)
    end
  end

  defp await_flow_message(contact_id, expected_body, 0) do
    flunk(
      "Timed out waiting for message body #{inspect(expected_body)} for contact #{contact_id}"
    )
  end

  defp await_flow_message(contact_id, expected_body, attempts) do
    case Glific.Messages.list_messages(%{
           filter: %{contact_id: contact_id},
           opts: %{limit: 1, order: :desc}
         }) do
      [%{body: ^expected_body} = message | _] ->
        message

      _ ->
        Process.sleep(@await_flow_message_interval_ms)
        await_flow_message(contact_id, expected_body, attempts - 1)
    end
  end

  defp enable_kaapi(attrs) do
    {:ok, credential} =
      Partners.create_credential(%{
        organization_id: attrs.organization_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{
          "api_key" => "sk_test_key"
        }
      })

    valid_update_attrs = %{
      keys: %{},
      secrets: %{
        "api_key" => "sk_test_key"
      },
      is_active: true,
      organization_id: attrs.organization_id,
      shortcode: "kaapi"
    }

    Partners.update_credential(credential, valid_update_attrs)
  end
end
