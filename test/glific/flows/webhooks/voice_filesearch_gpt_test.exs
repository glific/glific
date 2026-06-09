defmodule Glific.Flows.Webhooks.VoiceFilesearchGptTest do
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

  # Voice-specific callback format: includes voice_post_process metadata
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
      [node | _] = flow.nodes

      flow_attrs = %{
        flow_id: flow.id,
        flow_uuid: flow.uuid,
        contact_id: contact.id,
        organization_id: org_id,
        node_uuid: node.uuid,
        is_await_result: true,
        wakeup_at: DateTime.add(DateTime.utc_now(), 60)
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
end
