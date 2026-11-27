defmodule Glific.Flows.Webhooks.VoiceStsTest do
  use Glific.DataCase, async: false

  alias Glific.{
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Fixtures,
    Flows.Webhooks.KaapiChain,
    Flows.Webhooks.VoiceFilesearchGpt,
    Flows.Webhooks.VoiceSts,
    Partners,
    Seeds.SeedsDev
  }

  @audio_url "https://media.example.com/voice.ogg"
  @audio_bytes "fake-ogg-bytes"
  @sts_url "/api/v1/llm/chain/sts"

  setup %{organization_id: organization_id} do
    SeedsDev.seed_organizations()

    {:ok, _credential} =
      Partners.create_credential(%{
        organization_id: organization_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{"api_key" => "sk_test_key"},
        is_active: true
      })

    create_assistant(organization_id)
    contact = Fixtures.contact_fixture(%{organization_id: organization_id})
    flow = Fixtures.flow_fixture(%{organization_id: organization_id})

    fields = %{
      "organization_id" => organization_id,
      "flow_id" => flow.id,
      "contact_id" => contact.id,
      "assistant_id" => "asst_sts_test",
      "speech" => @audio_url,
      "result_name" => "result"
    }

    %{fields: fields}
  end

  defp create_assistant(organization_id) do
    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{
        name: "STS Test Assistant",
        organization_id: organization_id,
        kaapi_uuid: "kaapi-uuid-sts",
        assistant_display_id: "asst_sts_test"
      })
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        kaapi_version_number: 4,
        prompt: "You are a helpful voice assistant.",
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
    |> Repo.update!()
  end

  # Mocks the audio download and Kaapi, sending each STS request body to the test process.
  defp mock_kaapi(response \\ %Tesla.Env{status: 200, body: %{success: true, data: %{}}}) do
    test_pid = self()

    Tesla.Mock.mock(fn
      %{method: :get, url: @audio_url} ->
        %Tesla.Env{
          status: 200,
          body: @audio_bytes,
          headers: [{"content-type", "audio/ogg"}]
        }

      %{method: :post, url: url, body: body} ->
        if String.ends_with?(url, @sts_url), do: send(test_pid, {:sts, Jason.decode!(body)})
        response
    end)
  end

  defp sts_request(fields) do
    assert {:ok, _ack} = VoiceSts.call(fields, %{})
    assert_received {:sts, body}
    body
  end

  describe "call/2 request" do
    test "sends the audio, the assistant's stored config and the voice TTS step",
         %{fields: fields} do
      mock_kaapi()
      body = sts_request(fields)

      assert body["query"]["input"] == %{
               "type" => "audio",
               "content" => %{
                 "format" => "base64",
                 "value" => Base.encode64(@audio_bytes),
                 "mime_type" => "audio/ogg"
               }
             }

      assert body["config"]["llm"] == %{
               "id" => "kaapi-uuid-sts",
               "version" => 4,
               "conversation" => %{"auto_create" => true}
             }

      assert body["config"]["stt"] == %{"provider" => "google"}

      assert %{
               "provider" => "google",
               "params" => %{
                 "model" => "gemini-3.8-flash-lite-tts",
                 "voice" => voice,
                 "response_format" => "ogg"
               }
             } = body["config"]["tts"]

      assert is_binary(voice) and voice != ""
      assert body["callback_url"] =~ "/webhook/flow_resume"
    end

    test "tags the request metadata as a speech-to-speech chain", %{fields: fields} do
      mock_kaapi()
      metadata = sts_request(fields)["request_metadata"]

      assert %{
               "call_type" => "voice_sts",
               "webhook_name" => "voice-filesearch-gpt",
               "chain_blocks" => ["stt", "llm", "tts"],
               "chain_fallback" => "llm",
               "audio_size_bucket" => "0-1MB"
             } = metadata

      assert is_integer(metadata["kaapi_dispatch_ts"])
    end

    test "sends target_language as the STT output language, plus input language and instructions",
         %{fields: fields} do
      mock_kaapi()

      body =
        fields
        |> Map.merge(%{
          "target_language" => "hindi",
          "input_language" => "en-IN",
          "instructions" => "Keep proper nouns",
          "source_language" => "english"
        })
        |> sts_request()

      assert body["config"]["stt"] == %{
               "provider" => "google",
               "params" => %{
                 "output_language" => "hindi",
                 "input_language" => "en-IN",
                 "instructions" => "Keep proper nouns"
               }
             }
    end

    test "continues the conversation and uses the node voice", %{fields: fields} do
      mock_kaapi()

      body =
        fields
        |> Map.merge(%{"thread_id" => "conv_123", "voice" => "Kore"})
        |> sts_request()

      assert body["config"]["llm"]["conversation"] == %{"id" => "conv_123"}
      assert body["config"]["tts"]["params"]["voice"] == "Kore"
    end

    test "does not send blank or unresolved flow variables", %{fields: fields} do
      mock_kaapi()

      body =
        fields
        |> Map.merge(%{
          "thread_id" => "@results.voice.thread_id",
          "target_language" => "  ",
          "input_language" => "@contact.fields.lang",
          "instructions" => "",
          "voice" => "@contact.fields.voice"
        })
        |> sts_request()

      assert body["config"]["stt"] == %{"provider" => "google"}
      assert body["config"]["llm"]["conversation"] == %{"auto_create" => true}
      refute body["config"]["tts"]["params"]["voice"] =~ "@"
    end
  end

  describe "call/2 failures" do
    test "an unreachable voice note fails without calling Kaapi", %{fields: fields} do
      Tesla.Mock.mock(fn %{method: :get, url: @audio_url} ->
        %Tesla.Env{status: 404, body: ""}
      end)

      assert {:error, :invalid_media_url, "Could not download the voice note"} =
               VoiceSts.call(fields, %{})

      refute_received {:sts, _body}
    end

    test "a missing or non-https media URL fails", %{fields: fields} do
      assert {:error, :invalid_media_url, _} =
               VoiceSts.call(Map.delete(fields, "speech"), %{})

      assert {:error, :invalid_media_url, _} =
               VoiceSts.call(Map.put(fields, "speech", "http://insecure/a.ogg"), %{})
    end

    test "an unknown assistant fails before dispatch", %{fields: fields} do
      mock_kaapi()

      assert {:error, :invalid_input, reason} =
               VoiceSts.call(Map.put(fields, "assistant_id", "asst_missing"), %{})

      assert reason =~ "Assistant not found"
      refute_received {:sts, _body}
    end

    test "a Kaapi rejection fails the node with Kaapi's reason", %{fields: fields} do
      mock_kaapi(%Tesla.Env{status: 422, body: %{success: false, error: "bad config"}})

      assert {:error, _error_type, reason} = VoiceSts.call(fields, %{})
      assert reason =~ "bad config"
    end

    test "an organization without Kaapi credentials fails", %{fields: fields} do
      assert {:error, _error_type, _reason} =
               VoiceSts.call(Map.put(fields, "organization_id", "not-a-number"), %{})
    end
  end

  describe "handle_callback/3" do
    setup %{organization_id: organization_id} do
      log = Fixtures.webhook_log_fixture(%{organization_id: organization_id})

      base = %{
        "webhook_log_id" => log.id,
        "organization_id" => organization_id,
        "webhook_name" => "voice-filesearch-gpt",
        "call_type" => "voice_sts",
        "chain_blocks" => ["stt", "llm", "tts"],
        "total_blocks" => 3,
        "kaapi_dispatch_ts" => 1_000_000
      }

      block = fn index, message, extra ->
        base
        |> Map.merge(%{"block_index" => index, "message" => message, "output_type" => "text"})
        |> Map.merge(extra)
      end

      KaapiChain.record_intermediate(block.(1, "hello", %{}), 1_500_000)

      KaapiChain.record_intermediate(
        block.(2, "the answer", %{"thread_id" => "conv_9"}),
        2_000_000
      )

      %{base: base, ctx: %{organization_id: organization_id}}
    end

    test "a successful final callback carries the answer, transcript, audio and conversation",
         %{base: base, ctx: ctx} do
      response = Map.put(base, "message", "https://x/a.ogg")

      assert %{
               "message" => "the answer",
               "translated_text" => "the answer",
               "transcript" => "hello",
               "media_url" => "https://x/a.ogg",
               "thread_id" => "conv_9"
             } = VoiceSts.handle_callback(%{"success" => true}, response, ctx)
    end

    test "a degraded chain resumes with the text answer and no audio", %{base: base, ctx: ctx} do
      response = Map.merge(base, %{"chain_degraded" => true, "success" => true})

      assert %{
               "message" => "the answer",
               "transcript" => "hello",
               "media_url" => nil,
               "tts_failed" => true
             } = VoiceSts.handle_callback(%{"success" => false}, response, ctx)
    end

    test "a failed audio upload passes the failure and its reason through",
         %{base: base, ctx: ctx} do
      response = Map.merge(base, %{"success" => false, "reason" => "GCS upload failed"})
      assert VoiceSts.handle_callback(%{"success" => true}, response, ctx) == response
    end

    test "a failed chain passes through untouched", %{base: base, ctx: ctx} do
      response = Map.put(base, "reason", "boom")
      assert VoiceSts.handle_callback(%{"success" => false}, response, ctx) == response
    end

    test "a final callback with no logged answer resumes with an empty message",
         %{ctx: ctx, organization_id: organization_id} do
      empty_log = Fixtures.webhook_log_fixture(%{organization_id: organization_id})
      response = %{"webhook_log_id" => empty_log.id, "message" => "https://x/a.ogg"}

      assert %{"message" => "", "media_url" => "https://x/a.ogg"} =
               VoiceSts.handle_callback(%{"success" => true}, response, ctx)
    end
  end

  describe "VoiceFilesearchGpt routing" do
    setup %{organization_id: organization_id} do
      %{actor: %{organization_id: organization_id}}
    end

    test "with voice_sts_enabled the node dispatches to Kaapi speech-to-speech",
         %{fields: fields, actor: actor, organization_id: organization_id} do
      FunWithFlags.enable(:voice_sts_enabled, for_actor: actor)
      mock_kaapi()

      result = VoiceFilesearchGpt.call(fields, %{organization_id: organization_id})
      # The flag cache outlives the test's DB sandbox, so switch it back off here.
      FunWithFlags.disable(:voice_sts_enabled, for_actor: actor)

      assert {:ok, _ack} = result
      assert_received {:sts, _body}
    end

    test "with the flag off the node never calls speech-to-speech",
         %{fields: fields, actor: actor, organization_id: organization_id} do
      FunWithFlags.disable(:voice_sts_enabled, for_actor: actor)
      # The audio downloads fine and the STS endpoint answers, so only the flag keeps the node
      # off speech-to-speech; the legacy Gemini STT call is the one that fails.
      mock_kaapi()

      VoiceFilesearchGpt.call(fields, %{organization_id: organization_id})

      refute_received {:sts, _body}
    end

    test "speech-to-speech callbacks are shaped by VoiceSts", %{organization_id: organization_id} do
      response = %{"call_type" => "voice_sts", "reason" => "boom"}

      assert VoiceFilesearchGpt.handle_callback(%{"success" => false}, response, %{
               organization_id: organization_id
             }) == response
    end

    test "waits up to 120 seconds for the callback with the flag on, 60 with it off",
         %{actor: actor} do
      FunWithFlags.enable(:voice_sts_enabled, for_actor: actor)
      sts_wait = VoiceFilesearchGpt.wait_time_default()
      FunWithFlags.disable(:voice_sts_enabled, for_actor: actor)

      assert sts_wait == 120
      assert VoiceFilesearchGpt.wait_time_default() == 60
    end
  end
end
