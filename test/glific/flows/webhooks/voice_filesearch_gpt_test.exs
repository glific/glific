defmodule Glific.Flows.Webhooks.VoiceFilesearchGptTest do
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
    :ok
  end

  defp create_assistant(organization_id) do
    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{
        name: "Voice Test Assistant",
        organization_id: organization_id,
        kaapi_uuid: "kaapi-uuid-voice-test",
        assistant_display_id: "asst_test123"
      })
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        version_number: 1,
        kaapi_version_number: 1,
        prompt: "You are a helpful voice assistant.",
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

    assistant
  end

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

  defp build_voice_callback_params(
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
        "response" => %{
          "conversation_id" => "conv_voice_test_123",
          "output" => %{
            "type" => "text",
            "content" => %{"value" => message}
          }
        }
      },
      "metadata" => %{
        "organization_id" => organization_id,
        "flow_id" => flow_id,
        "contact_id" => contact_id,
        "signature" => signature,
        "timestamp" => timestamp,
        "webhook_log_id" => webhook_log_id,
        "result_name" => "filesearch",
        "voice_post_process" => %{
          "source_language" => "english",
          "target_language" => "english",
          "speech_engine" => ""
        }
      },
      "success" => success
    }
  end

  defp build_action(contact_id) do
    %Action{
      method: "FUNCTION",
      url: "voice-filesearch-gpt",
      headers: %{"Content-Type" => "application/json"},
      body:
        Jason.encode!(%{
          contact: %{"id" => contact_id},
          speech: "https://gcs.example.com/audio.ogg",
          assistant_id: "asst_test123",
          source_language: "en",
          target_language: "hi"
        })
    }
  end

  describe "voice-filesearch-gpt" do
    # Happy path: the flow is already in await state (simulating that the
    # voice-filesearch-gpt webhook fired and put it there). The Kaapi LLM
    # callback arrives at /kaapi/voice_flow_resume and the flow moves to
    # the success branch, sending the translated response.
    test "happy path callback - flow moves to success route after voice callback", %{
      conn: %{assigns: %{organization_id: org_id}} = conn
    } do
      {contact, webhook_log, flow} = build_await_context(org_id)

      expected_message = "This is the translated response"

      params =
        build_voice_callback_params(
          org_id,
          flow.id,
          contact.id,
          webhook_log.id,
          true,
          expected_message
        )

      conn = post(conn, "/kaapi/voice_flow_resume", params)
      assert json_response(conn, 200) == ""

      message = await_flow_message(contact.id, expected_message)
      assert message.body == expected_message
    end

    # Failure callback: Kaapi signals failure; the flow moves to the failure branch.
    test "failure callback - flow moves to failure route", %{
      conn: %{assigns: %{organization_id: org_id}} = conn
    } do
      {contact, webhook_log, flow} = build_await_context(org_id)

      params =
        build_voice_callback_params(
          org_id,
          flow.id,
          contact.id,
          webhook_log.id,
          false,
          "Kaapi error: voice processing failed"
        )

      conn = post(conn, "/kaapi/voice_flow_resume", params)
      assert json_response(conn, 200) == ""

      message = await_flow_message(contact.id, "failure")
      assert message.body == "failure"
    end

    # Timeout: the outbound Kaapi LLM call times out during webhook execution.
    # STT (Bhasini/Gemini) succeeds but the LLM call itself returns {:error, :timeout}.
    # execute_unified_voice_filesearch should return {:ok, ...} (not {:wait, ...})
    # and the webhook log should record the error.
    test "timeout - Bhasini STT succeeds but Kaapi LLM times out, webhook log records error", %{
      conn: %{assigns: %{organization_id: org_id}} = _conn
    } do
      _assistant = create_assistant(org_id)
      contact = Fixtures.contact_fixture(%{organization_id: org_id})

      flow = Flow.get_loaded_flow(org_id, "published", %{keyword: "call_and_wait"})

      flow_attrs = %{
        flow_id: flow.id,
        flow_uuid: flow.uuid,
        contact_id: contact.id,
        organization_id: org_id
      }

      {:ok, context} = FlowContext.create_flow_context(flow_attrs)
      context = Repo.preload(context, [:contact, :flow])

      action = build_action(contact.id)

      # Bhasini STT (Gemini) succeeds; Kaapi LLM times out
      Tesla.Mock.mock(fn
        %{method: :get, url: "https://gcs.example.com/audio.ogg"} ->
          %Tesla.Env{status: 200, body: "fake-audio-bytes"}

        %{method: :post, url: url} ->
          cond do
            String.contains?(url, "generativelanguage.googleapis.com") ->
              %Tesla.Env{
                status: 200,
                body: %{
                  candidates: [
                    %{content: %{parts: [%{text: Jason.encode!("test query")}]}}
                  ],
                  usageMetadata: %{
                    promptTokenCount: 5,
                    candidatesTokenCount: 3,
                    totalTokenCount: 8
                  }
                }
              }

            String.contains?(url, "/api/v1/llm/call") ->
              {:error, :timeout}

            true ->
              {:error, :timeout}
          end
      end)

      # When Kaapi LLM times out, execute_unified_voice_filesearch returns
      # {:ok, context, [failure_message]} (failure branch, NOT await)
      result = Webhook.execute_unified_voice_filesearch(action, context)
      assert match?({:ok, _, _}, result)

      # The webhook log created inside unified_llm_and_wait should record the timeout error
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
