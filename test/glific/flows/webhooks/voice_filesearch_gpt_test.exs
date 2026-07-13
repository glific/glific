defmodule Glific.Flows.Webhooks.VoiceFilesearchGptTest do
  use GlificWeb.ConnCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  import Glific.WebhookTestHelpers
  import Mock

  alias Glific.{
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Fixtures,
    Flows.Action,
    Flows.Flow,
    Flows.FlowContext,
    Flows.WebhookLog,
    Flows.Webhooks.Errors.SystemError,
    Flows.Webhooks.VoiceFilesearchGpt,
    Partners,
    Repo,
    Seeds.SeedsDev,
    ThirdParty.Gemini
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

  # voice_post_process's NMT path is gated on the org having GCS enabled
  # (organization.services["google_cloud_storage"]). Create that credential and
  # refresh the org cache so the in-test org reports GCS on. The DB row is rolled
  # back by the SQL sandbox, but the Partners org cache is a *global* Cachex store
  # that isn't — so clear it on_exit to keep the "GCS disabled" cases order-independent.
  defp enable_gcs(organization_id) do
    {:ok, _credential} =
      Partners.create_credential(%{
        organization_id: organization_id,
        shortcode: "google_cloud_storage",
        secrets: %{
          "bucket" => "mock-bucket-name",
          "service_account" =>
            Jason.encode!(%{
              project_id: "DEFAULT PROJECT ID",
              private_key_id: "DEFAULT API KEY",
              client_email: "DEFAULT CLIENT EMAIL",
              private_key: "DEFAULT PRIVATE KEY"
            })
        },
        is_active: true
      })

    organization = Partners.get_organization!(organization_id)
    Partners.fill_cache(organization)

    on_exit(fn ->
      Partners.remove_organization_cache(organization_id, organization.shortcode)
    end)
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
      type: "call_webhook",
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

    # Timeout: the outbound Kaapi LLM call times out in the worker.
    # Gemini STT succeeds but the LLM call returns {:error, :timeout}, so
    # VoiceFilesearchGpt.call returns %{success: false} and the webhook log records the error.
    test "timeout - Gemini STT succeeds but Kaapi LLM times out, webhook log records error", %{
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

      # Gemini STT succeeds; Kaapi LLM times out
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

      assert {:wait, _parked, []} = Action.execute(action, context, [])
      Oban.drain_queue(queue: :gpt_webhook_queue)

      # The webhook log created in do_oban should record the timeout error
      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log != nil
      assert log.error != nil
    end

    # Stage 1 (STT) failure: Gemini speech-to-text fails (audio download 404),
    # so VoiceFilesearchGpt.call returns %{success: false} WITHOUT making the Kaapi LLM
    # call, and the flow wakes on the Failure branch.
    test "STT failure - speech-to-text fails, no LLM call, flow records the error", %{
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

      # Audio download fails -> STT returns a failure -> no /api/v1/llm/call is made
      # (no POST clause needed; a POST would raise Tesla.Mock and fail the test).
      Tesla.Mock.mock(fn
        %{method: :get, url: "https://gcs.example.com/audio.ogg"} ->
          %Tesla.Env{status: 404, body: ""}
      end)

      assert {:wait, _parked, []} = Action.execute(action, context, [])
      Oban.drain_queue(queue: :gpt_webhook_queue)

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log != nil
      assert log.error != nil
    end

    # Stage 2 (Kaapi LLM) failure (non-timeout): STT succeeds but the unified LLM call
    # returns an API error (500); VoiceFilesearchGpt.call returns %{success: false} and
    # the flow records the error.
    test "Kaapi LLM API error - STT succeeds but LLM call returns 500, flow records the error",
         %{conn: %{assigns: %{organization_id: org_id}} = _conn} do
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

      Tesla.Mock.mock(fn
        %{method: :get, url: "https://gcs.example.com/audio.ogg"} ->
          %Tesla.Env{status: 200, body: "fake-audio-bytes"}

        %{method: :post, url: url} ->
          cond do
            String.contains?(url, "generativelanguage.googleapis.com") ->
              %Tesla.Env{
                status: 200,
                body: %{
                  candidates: [%{content: %{parts: [%{text: Jason.encode!("test query")}]}}],
                  usageMetadata: %{
                    promptTokenCount: 5,
                    candidatesTokenCount: 3,
                    totalTokenCount: 8
                  }
                }
              }

            String.contains?(url, "/api/v1/llm/call") ->
              %Tesla.Env{status: 500, body: %{"error" => "internal server error"}}

            true ->
              %Tesla.Env{status: 500, body: %{}}
          end
      end)

      assert {:wait, _parked, []} = Action.execute(action, context, [])
      Oban.drain_queue(queue: :gpt_webhook_queue)

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log != nil
      assert log.error != nil
    end
  end

  describe "voice_post_process/3" do
    test "reports SystemError when Kaapi callback says success=true but message is empty" do
      organization_id = 1

      response = %{
        "message" => "",
        "voice_post_process" => %{
          "source_language" => "english",
          "target_language" => "hindi"
        },
        "flow_id" => 1,
        "contact_id" => 2,
        "webhook_log_id" => 1
      }

      {exception, tags} =
        capture_appsignal(fn ->
          result = VoiceFilesearchGpt.voice_post_process(organization_id, response)

          assert result["translated_text"] == ""
          assert is_nil(result["media_url"])
        end)

      assert %SystemError{} = exception
      assert tags.webhook_name == "voice-filesearch-gpt"
      # 200 distinguishes this from a 5xx/timeout — the call succeeded at the
      # HTTP layer, the body was just unusable.
      assert tags.http_status == 200
      assert tags.reason =~ "empty"
    end

    # Stage 3 (NMT+TTS) failure: a non-empty answer, but the Gemini NMT+TTS step fails
    # (GCS not enabled for org 1 in test) — voice_post_process falls back to the
    # untranslated text with no audio rather than crashing.
    test "returns untranslated text and no audio when NMT+TTS fails (GCS disabled)" do
      response = %{
        "message" => "Hello there",
        "voice_post_process" => %{
          "source_language" => "english",
          "target_language" => "hindi"
        }
      }

      result = VoiceFilesearchGpt.voice_post_process(1, response)

      assert result["translated_text"] == "Hello there"
      assert is_nil(result["media_url"])
    end

    # Stage 3 (NMT+TTS) success: source != target, GCS enabled, supported languages —
    # Gemini.nmt_text_to_speech translates + generates audio; voice_post_process merges
    # the translated_text + media_url into the response.
    test "NMT+TTS success: translates and merges translated_text + media_url" do
      enable_gcs(1)
      media_url = "https://storage.googleapis.com/mock-bucket/Gemini/outbound/voice.mp3"

      response = %{
        "message" => "Hello there",
        "voice_post_process" => %{
          "source_language" => "english",
          "target_language" => "hindi"
        }
      }

      with_mock(Gemini, [:passthrough],
        nmt_text_to_speech: fn _org, _text, "english", "hindi", _opts ->
          %{success: true, translated_text: "नमस्ते", media_url: media_url}
        end
      ) do
        result = VoiceFilesearchGpt.voice_post_process(1, response)

        assert result["translated_text"] == "नमस्ते"
        assert result["media_url"] == media_url
      end
    end

    # Stage 3 same source/target language: no translation, plain TTS of the answer.
    # tts_only routes a non-English same-language pair to Gemini.text_to_speech.
    test "same source/target language: TTS only (no translation), returns audio" do
      media_url = "https://storage.googleapis.com/mock-bucket/Gemini/outbound/tts.mp3"

      response = %{
        "message" => "Namaste doctor",
        "voice_post_process" => %{
          "source_language" => "hindi",
          "target_language" => "hindi"
        }
      }

      with_mock(Gemini, [:passthrough],
        text_to_speech: fn _org, text ->
          %{success: true, media_url: media_url, translated_text: text}
        end
      ) do
        result = VoiceFilesearchGpt.voice_post_process(1, response)

        # same language -> text spoken as-is, no translation
        assert result["translated_text"] == "Namaste doctor"
        assert result["media_url"] == media_url
      end
    end

    # Stage 3 unsupported language: GCS is on, but the target isn't a Gemini-supported
    # language, so the valid_language? guard fails before any API call and we fall back
    # to the untranslated text with no audio.
    test "unsupported target language: no audio, falls back to untranslated text" do
      enable_gcs(1)

      response = %{
        "message" => "Hello there",
        "voice_post_process" => %{
          "source_language" => "english",
          "target_language" => "klingon"
        }
      }

      result = VoiceFilesearchGpt.voice_post_process(1, response)

      assert result["translated_text"] == "Hello there"
      assert is_nil(result["media_url"])
    end

    # Stage 3 both languages blank (the node body default): "" == "" -> same-language
    # path -> plain TTS, no translation.
    test "both languages blank: defaults to TTS only (no translation)" do
      media_url = "https://storage.googleapis.com/mock-bucket/Gemini/outbound/blank.mp3"

      response = %{
        "message" => "Hello there",
        "voice_post_process" => %{
          "source_language" => "",
          "target_language" => ""
        }
      }

      with_mock(Gemini, [:passthrough],
        text_to_speech: fn _org, text ->
          %{success: true, media_url: media_url, translated_text: text}
        end
      ) do
        result = VoiceFilesearchGpt.voice_post_process(1, response)

        assert result["translated_text"] == "Hello there"
        assert result["media_url"] == media_url
      end
    end
  end

  # Runs `fun` with Appsignal.send_error and Appsignal.Span.set_sample_data
  # mocked. Returns {exception, tags} captured from the production reporting call.
  defp capture_appsignal(fun) do
    test_pid = self()

    with_mocks([
      {Appsignal, [:passthrough],
       [
         send_error: fn ex, _stack, configurator ->
           send(test_pid, {:appsignal_exception, ex})
           configurator.(:fake_span)
           :ok
         end
       ]},
      {Appsignal.Span, [:passthrough],
       [
         set_sample_data: fn _span, key, value ->
           send(test_pid, {:appsignal_tag, key, value})
           :fake_span
         end
       ]}
    ]) do
      fun.()
    end

    exception =
      receive do
        {:appsignal_exception, ex} -> ex
      after
        100 -> flunk("Appsignal.send_error was not called")
      end

    tags =
      receive do
        {:appsignal_tag, "tags", t} -> t
      after
        100 -> %{}
      end

    {exception, tags}
  end

  # Dispatch-level regression: an invalid (non-https) audio URL must return a structured
  # failure from call/2 rather than raising a CaseClauseError. The happy/STT-failure/LLM-error
  # dispatch paths are already exercised by the e2e tests above.
  describe "voice-filesearch-gpt dispatch" do
    test "returns structured failure (no CaseClauseError) when the audio URL is invalid" do
      contact = Fixtures.contact_fixture()

      fields = %{
        "organization_id" => 1,
        "flow_id" => 1,
        "contact_id" => contact.id,
        "assistant_id" => "asst_voice_bad_url",
        # http (not https) → validate_media returns invalid
        "speech" => "http://example.com/audio.ogg",
        "source_language" => "english",
        "target_language" => "hindi",
        "webhook_log_id" => 1,
        "result_name" => "result"
      }

      assert VoiceFilesearchGpt.call(fields, %{}) ==
               %{success: false, reason: "Media URL is invalid", error_type: :invalid_media_url}
    end
  end
end
