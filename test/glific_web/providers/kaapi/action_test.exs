defmodule GlificWeb.Providers.Kaapi.ActionTest do
  use GlificWeb.ConnCase
  import Ecto.Query

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

      Tesla.Mock.mock(fn
        %Tesla.Env{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{
              error: nil,
              data: %{
                message: "Response creation started",
                status: "processing",
                success: true
              }
            }
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
          "endpoint" => "This is not a secretapi/v1/responses",
          "flow_id" => flow.id,
          "message" => @kaapi_response,
          "organization_id" => organization_id,
          "response_id" => "resp_68826b142198819881bce999ccd87a750d0635d313bf2c6f",
          "signature" => signature,
          "status" => "success",
          "timestamp" => timestamp,
          "webhook_log_id" => webhook_log.id,
          "result_name" => "filesearch"
        },
        "success" => true
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

      FunWithFlags.disable(:is_kaapi_enabled,
        for_actor: %{organization_id: organization_id}
      )
    end

    test "wakeup_one/1 will process all the context for the contact, without a message from upstream when kaapi enabled",
         %{organization_id: organization_id} = _attrs do
      # activate kaapi
      enable_kaapi(%{organization_id: organization_id})

      FunWithFlags.enable(:is_kaapi_enabled,
        for_actor: %{organization_id: organization_id}
      )

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

      FunWithFlags.disable(:is_kaapi_enabled,
        for_actor: %{organization_id: organization_id}
      )
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

      Tesla.Mock.mock(fn
        %Tesla.Env{method: :post} ->
          %Tesla.Env{
            body: %{
              error: "Not found",
              success: false
            }
          }
      end)

      message_stream = []

      assert {:ok, flow_context, [message]} = Action.execute(action, context, message_stream)

      # error should be logged
      webhook_log = Repo.get_by(WebhookLog, %{url: "filesearch-gpt"})
      assert webhook_log.error == "{\"error\":\"Not found\",\"success\":false}"
      assert webhook_log.status_code == 400

      # It should go to the failure category and send the failure message,
      # since the node in the failure category has the failure message as its body.
      assert message.body == "Failure"
      assert flow_context.id == context.id

      FunWithFlags.disable(:is_kaapi_enabled,
        for_actor: %{organization_id: organization_id}
      )
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
          "{\n\"question\": \"tell me a fact about consistency\",\n  \"flow_id\": \"@flow.id\",\n  \"endpoint\": \"This is not a secretapi/v1/responsess\",\n
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
        %Tesla.Env{method: :post} ->
          %Tesla.Env{
            status: 404,
            body: %{
              error: "Assistant not found or not active",
              success: false
            }
          }
      end)

      message_stream = []
      assert {:ok, flow_context, [message]} = Action.execute(action, context, message_stream)

      # error should be logged
      webhook_log =
        WebhookLog
        |> where(url: "filesearch-gpt")
        |> order_by(desc: :inserted_at)
        |> limit(1)
        |> Repo.one()

      assert webhook_log.error ==
               "{\"error\":\"Assistant not found or not active\",\"success\":false}"

      # It should go to the failure category and send the failure message,
      # since the node in the failure category has the failure message as its body.
      assert message.body == "Failure"
      assert flow_context.id == context.id

      FunWithFlags.disable(:is_kaapi_enabled,
        for_actor: %{organization_id: organization_id}
      )
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
          "{\n\"question\": \"tell me a fact about consistency\",\n  \"flow_id\": \"@flow.id\",\n  \"endpoint\": \"This is not a secretapi/v1/responses\",\n
          \"contact_id\": \"@contact.id\",\n  \"callback_url\": \"https://91e372283c55/webhook/flow_resume\",\n  \"assistant_id\": \"asst_pJxxD\"\n}",
        method: "FUNCTION",
        headers: %{
          Accept: "application/json",
          "Content-Type": "application/json"
        },
        result_name: "filesearch",
        node_uuid: "Test UUID",
        wait_time: 5
      }

      Tesla.Mock.mock(fn
        %Tesla.Env{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{
              error: nil,
              data: %{
                message: "Response creation started",
                status: "processing",
                success: true
              }
            }
          }
      end)

      message_stream = []

      Action.execute(action, context, message_stream)

      # Reduce wait_time to 10 seconds(above in action.wait_time) to avoid actual 60-second delay in test.
      # This simulates the behavior of waiting for a webhook response and triggering the flow
      # via the wakeup_flows scheduler, also makes the test faster and avoids ExUnit timeouts.
      :timer.sleep(6_000)
      Partners.perform_all(&FlowContext.wakeup_flows/1, nil, [])

      [message | _messages] =
        Glific.Messages.list_messages(%{
          filter: %{contact_id: contact.id},
          opts: %{limit: 1, order: :desc}
        })

      # It should go to the failure after not getting any resposne from kaapi
      # after a minute and send the failure message,
      assert message.body == "failure"

      webhook_log =
        from(w in WebhookLog,
          where: w.flow_context_id == ^context.id,
          order_by: [desc: w.inserted_at],
          limit: 1
        )
        |> Repo.one()

      assert webhook_log.error == "Timeout: taking long to process response"

      FunWithFlags.disable(:is_kaapi_enabled,
        for_actor: %{organization_id: organization_id}
      )
    end

    test "logs descriptive error when kaapi is not active", %{conn: conn} do
      organization_id = conn.assigns.organization_id

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

      FunWithFlags.disable(:is_kaapi_enabled,
        for_actor: %{organization_id: organization_id}
      )
    end
  end

  describe "Call a webhook for FileSearch-GPT when Unified API is enabled" do
    test "executes unified API filesearch when unified_api_enabled flag is on",
         %{conn: conn} do
      organization_id = conn.assigns.organization_id

      # activate kaapi
      enable_kaapi(%{organization_id: organization_id})

      FunWithFlags.enable(:is_kaapi_enabled,
        for_actor: %{organization_id: organization_id}
      )

      FunWithFlags.enable(:unified_api_enabled,
        for_actor: %{organization_id: organization_id}
      )

      # Create an Assistant record with kaapi_uuid and assistant_display_id
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Test Unified Assistant",
          organization_id: organization_id,
          kaapi_uuid: "kaapi-uuid-test-123",
          assistant_display_id: "asst_pJxxD"
        })
        |> Repo.insert()

      # Create an AssistantConfigVersion with version_number
      {:ok, config_version} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          version_number: 3,
          prompt: "You are a helpful assistant.",
          provider: "openai",
          model: "gpt-4o",
          settings: %{},
          status: :ready,
          organization_id: organization_id
        })
        |> Repo.insert()

      # Set the active config version on the assistant
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

      [message | _messages] =
        Glific.Messages.list_messages(%{
          filter: %{contact_id: contact.id},
          opts: %{limit: 1, order: :desc}
        })

      assert message.body == @kaapi_response

      # Cleanup flags
      FunWithFlags.disable(:unified_api_enabled,
        for_actor: %{organization_id: organization_id}
      )

      FunWithFlags.disable(:is_kaapi_enabled,
        for_actor: %{organization_id: organization_id}
      )
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

  test "should add the error in webhook log when getting the error response from kaapi",
       %{conn: conn} do
    organization_id = conn.assigns.organization_id
    # activate kaapi
    enable_kaapi(%{organization_id: organization_id})

    FunWithFlags.enable(:is_kaapi_enabled,
      for_actor: %{organization_id: organization_id}
    )

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

    Tesla.Mock.mock(fn
      %Tesla.Env{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            error: nil,
            data: %{
              message: "Response creation started",
              status: "processing",
              success: true
            }
          }
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

    error_message =
      "Invalid 'previous_response_id': '@results.filesearch'. Expected an ID that contains letters, numbers, underscores, or dashes, but this value contained additional characters."

    params = %{
      "data" => %{
        "contact_id" => contact.id,
        "flow_id" => flow.id,
        "organization_id" => organization_id,
        "signature" => signature,
        "timestamp" => timestamp,
        "webhook_log_id" => webhook_log.id,
        "result_name" => "filesearch"
      },
      "error" => error_message,
      "metadata" => nil,
      "success" => false
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

    assert message.body == "failure"

    # webhook log should be updated with the error response
    updated_webhook_log = Repo.get_by(WebhookLog, %{id: webhook_log.id})

    assert updated_webhook_log.response_json["message"] == error_message
    assert updated_webhook_log.response_json["success"] == false
    assert updated_webhook_log.response_json["thread_id"] == nil
  end
end
