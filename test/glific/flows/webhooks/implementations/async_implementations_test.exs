defmodule Glific.Flows.Webhooks.AsyncImplementationsTest do
  @moduledoc """
  Contract tests for the four async webhook implementation modules.

  Verifies the behaviour surface that is pure (no Kaapi/HTTP): `name/0`, `webhook_name/0`
  (which now equals `name/0` — the node URL), `mode/0`, and `handle_resume/2`. The worker-
  phase `call/2` dispatch path is covered in the per-webhook callback tests.
  """
  use Glific.DataCase, async: false

  import Mock

  alias Glific.Clients.CommonWebhook

  alias Glific.Flows.Webhooks.{
    FilesearchGpt,
    SpeechToText,
    TextToSpeech,
    VoiceFilesearchGpt
  }

  describe "name/0, webhook_name/0, mode/0" do
    test "speech_to_text" do
      assert SpeechToText.name() == "speech_to_text"
      assert SpeechToText.webhook_name() == "speech_to_text"
      assert SpeechToText.mode() == :async
    end

    test "text_to_speech" do
      assert TextToSpeech.name() == "text_to_speech"
      assert TextToSpeech.webhook_name() == "text_to_speech"
      assert TextToSpeech.mode() == :async
    end

    test "filesearch_gpt — webhook_name equals the node URL" do
      assert FilesearchGpt.name() == "filesearch-gpt"
      assert FilesearchGpt.webhook_name() == "filesearch-gpt"
      assert FilesearchGpt.mode() == :async
    end

    test "voice_filesearch_gpt — webhook_name equals the node URL" do
      assert VoiceFilesearchGpt.name() == "voice-filesearch-gpt"
      assert VoiceFilesearchGpt.webhook_name() == "voice-filesearch-gpt"
      assert VoiceFilesearchGpt.mode() == :async
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

    test "filesearch_gpt returns the parsed response unchanged" do
      response = %{"message" => "an answer"}
      assert {:ok, ^response} = FilesearchGpt.handle_resume(response, %{organization_id: 1})
    end

    test "voice_filesearch_gpt post-processes the response via voice_post_process/3" do
      response = %{"message" => "an answer"}

      with_mock CommonWebhook, [:passthrough],
        voice_post_process: fn 1, true, ^response -> Map.put(response, "processed", true) end do
        assert {:ok, %{"processed" => true}} =
                 VoiceFilesearchGpt.handle_resume(response, %{organization_id: 1, success: true})

        assert_called(CommonWebhook.voice_post_process(1, true, response))
      end
    end
  end
end
