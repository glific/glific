defmodule Glific.Flows.Webhooks.AsyncImplementationsTest do
  @moduledoc """
  Contract tests for the four async webhook implementation modules.

  Verifies the behaviour surface that is pure (no Kaapi/HTTP): the node URL `name/0`
  vs the observability `webhook_name/0`, `mode/0`, and `handle_resume/2`. The call/2
  dispatch path is covered end-to-end in the per-webhook callback tests and in
  async_support_test.exs.
  """
  use Glific.DataCase, async: false

  import Mock

  alias Glific.Clients.CommonWebhook

  alias Glific.Flows.Webhooks.{
    SpeechToText,
    TextToSpeech,
    UnifiedLlm,
    UnifiedVoiceLlm
  }

  describe "name/0, webhook_name/0, mode/0" do
    test "speech_to_text uses the same string for node URL and observability name" do
      assert SpeechToText.name() == "speech_to_text"
      assert SpeechToText.webhook_name() == "speech_to_text"
      assert SpeechToText.mode() == :async
    end

    test "text_to_speech uses the same string for node URL and observability name" do
      assert TextToSpeech.name() == "text_to_speech"
      assert TextToSpeech.webhook_name() == "text_to_speech"
      assert TextToSpeech.mode() == :async
    end

    test "unified_llm node URL differs from its observability name" do
      assert UnifiedLlm.name() == "filesearch-gpt"
      assert UnifiedLlm.webhook_name() == "unified-llm-call"
      assert UnifiedLlm.mode() == :async
    end

    test "unified_voice_llm node URL differs from its observability name" do
      assert UnifiedVoiceLlm.name() == "voice-filesearch-gpt"
      assert UnifiedVoiceLlm.webhook_name() == "unified-voice-llm-call"
      assert UnifiedVoiceLlm.mode() == :async
    end
  end

  describe "handle_resume/2" do
    test "speech_to_text returns the parsed response unchanged" do
      response = %{"message" => "transcribed text"}
      assert {:ok, ^response} = SpeechToText.handle_resume(response, %{organization_id: 1})
    end

    test "text_to_speech returns the parsed response unchanged" do
      response = %{"message" => "https://gcs/audio.mp3"}
      assert {:ok, ^response} = TextToSpeech.handle_resume(response, %{organization_id: 1})
    end

    test "unified_llm returns the parsed response unchanged" do
      response = %{"message" => "an answer"}
      assert {:ok, ^response} = UnifiedLlm.handle_resume(response, %{organization_id: 1})
    end

    test "unified_voice_llm post-processes the response via voice_post_process/3" do
      response = %{"message" => "an answer"}

      with_mock CommonWebhook, [:passthrough],
        voice_post_process: fn 1, true, ^response -> Map.put(response, "processed", true) end do
        assert {:ok, %{"processed" => true}} =
                 UnifiedVoiceLlm.handle_resume(response, %{organization_id: 1, success: true})

        assert_called(CommonWebhook.voice_post_process(1, true, response))
      end
    end
  end
end
