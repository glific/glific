defmodule GlificWeb.Flows.FlowResumeControllerTest do
  use GlificWeb.ConnCase
  import Ecto.Query

  alias Glific.{
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

  describe "Call a webhook for FileSearch-GPT when Kaapi is enabled" do
    test "executes webhook action when type is `call_webhook`",
         %{conn: conn} do
      organization_id = conn.assigns.organization_id

      # activate kaapi
      enable_kaapi(%{organization_id: organization_id})

      FunWithFlags.enable(:is_kaapi_enabled,
        for_actor: %{organization_id: organization_id}
      )

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
          "{\n\"question\": \"tell me a fact about consistency\",\n  \"flow_id\": \"@flow.id\",\n  \"endpoint\": \"http://0.0.0.0:8000/api/v1/responses\",\n
          \"contact_id\": \"@contact.id\",\n  \"callback_url\": \"https://91e372283c55/webhook/flow_resume\",\n  \"assistant_id\": \"asst_pJxxD\"\n}",
        method: "FUNCTION",
        headers: %{
          Accept: "application/json",
          "Content-Type": "application/json"
        },
        result_name: "filesearch",
        node_uuid: "Test UUID"
      }

      Tesla.Mock.mock(fn
        %Tesla.Env{method: :post, url: "http://0.0.0.0:8000/api/v1/responses"} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                :success => true,
                "data" => %{
                  "message" => "Response creation started",
                  "status" => "processing",
                  "success" => true
                },
                "success" => true
              })
          }
      end)

      message_stream = []

      # execute the webhook node
      Action.execute(action, context, message_stream)

      webhook_log = Repo.get_by(WebhookLog, %{url: "filesearch-gpt"})

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

      params = %{
        "data" => %{
          "callback" =>
            "https://api.glific.glific.com/webhook/flow_resume?organization_id=1&flow_id=16&contact_id=16&timestamp=1753377554424136&signature=97075c37cbcd0b97dc7a18d754656770d0613d1869f0ed500c041c7e01c20d2f",
          "chunks" => [],
          "contact_id" => contact.id,
          "diagnostics" => %{
            "input_tokens" => 27,
            "model" => "gpt-4o-2024-08-06",
            "output_tokens" => 343,
            "total_tokens" => 370
          },
          "endpoint" => "http://0.0.0.0:8000/api/v1/responses",
          "flow_id" => flow.id,
          "message" => @kaapi_response,
          "organization_id" => organization_id,
          "response_id" => "resp_68826b142198819881bce999ccd87a750d0635d313bf2c6f",
          "signature" => signature,
          "status" => "success",
          "timestamp" => timestamp,
          "webhook_log_id" => webhook_log.id,
          "result_name" => "filesearch"
        }
      }

      conn =
        conn
        |> post("/webhook/flow_resume", params)

      assert json_response(conn, 200) == ""

      [message | _messages] =
        Glific.Messages.list_messages(%{
          filter: %{contact_id: contact.id},
          opts: %{limit: 1, order: :desc}
        })

      # once a response is received the flow moves to next node i.e. send the message which is @results.response.message
      assert message.body == @kaapi_response

      # webhook log should be updated with the callback response
      update_webhook_log = Repo.get_by(WebhookLog, %{id: webhook_log.id})

      assert update_webhook_log.response_json["message"] == @kaapi_response
    end

    test "logs descriptive error when webhook endpoint does not exist", %{conn: conn} do
      organization_id = conn.assigns.organization_id

      # activate kaapi
      enable_kaapi(%{organization_id: organization_id})

      FunWithFlags.enable(:is_kaapi_enabled,
        for_actor: %{organization_id: organization_id}
      )

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
          "{\n\"question\": \"tell me a fact about consistency\",\n  \"flow_id\": \"@flow.id\",\n  \"endpoint\": \"wrong_endpoint\",\n
          \"contact_id\": \"@contact.id\",\n  \"callback_url\": \"https://91e372283c55/webhook/flow_resume\",\n  \"assistant_id\": \"asst_pJxxD\"\n}",
        method: "FUNCTION",
        headers: %{
          Accept: "application/json",
          "Content-Type": "application/json"
        },
        result_name: "filesearch",
        node_uuid: "Test UUID"
      }

      Tesla.Mock.mock(fn
        %Tesla.Env{method: :post, url: "wrong_endpoint"} ->
          %Tesla.Env{
            body: "{\"detail\":\"Not Found\"}"
          }
      end)

      message_stream = []

      Action.execute(action, context, message_stream)

      # error should be logged
      webhook_log = Repo.get_by(WebhookLog, %{url: "filesearch-gpt"})
      assert webhook_log.error == "{\"detail\":\"Not Found\"}"
      assert webhook_log.status_code == 400

      [message | _messages] =
        Glific.Messages.list_messages(%{
          filter: %{contact_id: contact.id},
          opts: %{limit: 1, order: :desc}
        })

      # It should go to the failure category and send the failure message,
      # since the node in the failure category has the failure message as its body.
      assert message.body == "failure"
    end

    test "logs descriptive error when assistant id is invalid", %{conn: conn} do
      organization_id = conn.assigns.organization_id

      # activate kaapi
      enable_kaapi(%{organization_id: organization_id})

      FunWithFlags.enable(:is_kaapi_enabled,
        for_actor: %{organization_id: organization_id}
      )

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
          "{\n\"question\": \"tell me a fact about consistency\",\n  \"flow_id\": \"@flow.id\",\n  \"endpoint\": \"http://0.0.0.0:8000/api/v1/responses\",\n
          \"contact_id\": \"@contact.id\",\n  \"callback_url\": \"https://91e372283c55/webhook/flow_resume\",\n  \"assistant_id\": \"asst_pJxxD\"\n}",
        method: "FUNCTION",
        headers: %{
          Accept: "application/json",
          "Content-Type": "application/json"
        },
        result_name: "filesearch",
        node_uuid: "Test UUID"
      }

      # when endpoint is wrong
      Tesla.Mock.mock(fn
        %Tesla.Env{method: :post, url: "http://0.0.0.0:8000/api/v1/responses"} ->
          %Tesla.Env{
            body: "{\"detail\":\"Not Found\"}"
          }
      end)

      message_stream = []

      Tesla.Mock.mock(fn
        %Tesla.Env{method: :post, url: "http://0.0.0.0:8000/api/v1/responses"} ->
          %Tesla.Env{
            status: 404,
            body:
              "{\"success\":false,\"data\":null,\"error\":\"Assistant not found or not active\",\"metadata\":null}"
          }
      end)

      Action.execute(action, context, message_stream)

      # error should be logged
      webhook_log =
        WebhookLog
        |> where(url: "filesearch-gpt")
        |> order_by(desc: :inserted_at)
        |> limit(1)
        |> Repo.one()

      assert webhook_log.error ==
               "{\"success\":false,\"data\":null,\"error\":\"Assistant not found or not active\",\"metadata\":null}"

      [message | _messages] =
        Glific.Messages.list_messages(%{
          filter: %{contact_id: contact.id},
          opts: %{limit: 1, order: :desc}
        })

      # It should go to the failure category and send the failure message,
      # since the node in the failure category has the failure message as its body.
      assert message.body == "failure"
    end

    test "Send to failure category if no response is received from Kaapi after waiting for 60 seconds",
         %{conn: conn} do
      organization_id = conn.assigns.organization_id
      # activate kaapi
      enable_kaapi(%{organization_id: organization_id})

      FunWithFlags.enable(:is_kaapi_enabled,
        for_actor: %{organization_id: organization_id}
      )

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
          "{\n\"question\": \"tell me a fact about consistency\",\n  \"flow_id\": \"@flow.id\",\n  \"endpoint\": \"http://0.0.0.0:8000/api/v1/responses\",\n
          \"contact_id\": \"@contact.id\",\n  \"callback_url\": \"https://91e372283c55/webhook/flow_resume\",\n  \"assistant_id\": \"asst_pJxxD\"\n}",
        method: "FUNCTION",
        headers: %{
          Accept: "application/json",
          "Content-Type": "application/json"
        },
        result_name: "filesearch",
        node_uuid: "Test UUID",
        wait_time: 10
      }

      Tesla.Mock.mock(fn
        %Tesla.Env{method: :post, url: "http://0.0.0.0:8000/api/v1/responses"} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                :success => true,
                "data" => %{
                  "message" => "Response creation started",
                  "status" => "processing",
                  "success" => true
                },
                "success" => true
              })
          }
      end)

      message_stream = []

      Action.execute(action, context, message_stream)

      # Reduce wait_time to 10 seconds(above in action.wait_time) to avoid actual 60-second delay in test.
      # This simulates the behavior of waiting for a webhook response and triggering the flow
      # via the wakeup_flows scheduler, also makes the test faster and avoids ExUnit timeouts.
      :timer.sleep(11_000)
      Partners.perform_all(&FlowContext.wakeup_flows/1, nil, [])

      [message | _messages] =
        Glific.Messages.list_messages(%{
          filter: %{contact_id: contact.id},
          opts: %{limit: 1, order: :desc}
        })

      # It should go to the failure after not getting any resposne from kaapi
      # after a minute and send the failure message,
      assert message.body == "failure"
    end
  end

  defp enable_kaapi(attrs) do
    {:ok, credential} =
      Partners.create_credential(%{
        organization_id: attrs.organization_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{
          "api_key" => "sk_3fa22108-f464-41e5-81d9-d8a298854430"
        }
      })

    valid_update_attrs = %{
      keys: %{},
      secrets: %{
        "api_key" => "sk_3fa22108-f464-41e5-81d9-d8a298854430"
      },
      is_active: true,
      organization_id: attrs.organization_id,
      shortcode: "kaapi"
    }

    Partners.update_credential(credential, valid_update_attrs)
  end
end
