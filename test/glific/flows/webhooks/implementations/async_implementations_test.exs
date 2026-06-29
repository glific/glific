defmodule Glific.Flows.Webhooks.AsyncImplementationsTest do
  @moduledoc """
  Contract tests for the four async webhook implementation modules.

  Verifies the behaviour surface that is pure (no Kaapi/HTTP): `name/0` and `mode/0`.
  The worker-phase `call/2` dispatch path is covered in the per-webhook callback tests.
  """
  use Glific.DataCase, async: false

  alias Glific.Flows.Webhooks.Kaapi, as: KaapiSupport

  alias Glific.Flows.Webhooks.{
    FilesearchGpt,
    SpeechToText,
    TextToSpeech,
    VoiceFilesearchGpt
  }

  describe "call/2 with malformed flow metadata routes to a failure result" do
    # Unparseable organization_id/flow_id/contact_id -> parse_flow_fields returns
    # {:error, ...}, which each module must turn into a %{success: false} result (not a crash).
    @bad_meta %{"organization_id" => "x", "flow_id" => "y", "contact_id" => "z"}

    test "speech_to_text" do
      fields = Map.put(@bad_meta, "speech", "https://x.test/a.ogg")
      assert %{success: false, reason: _} = SpeechToText.call(fields, %{})
    end

    test "text_to_speech" do
      assert %{success: false, reason: _} =
               TextToSpeech.call(Map.put(@bad_meta, "text", "hi"), %{})
    end

    test "filesearch_gpt" do
      fields = Map.put(@bad_meta, "question", "hi")
      assert %{success: false, reason: _} = FilesearchGpt.call(fields, %{})
    end

    test "voice_filesearch_gpt" do
      assert %{success: false, reason: _} =
               VoiceFilesearchGpt.call(Map.put(@bad_meta, "speech", "x"), %{})
    end
  end

  describe "Kaapi.validate_media/1" do
    test "accepts an https URL" do
      assert :ok = KaapiSupport.validate_media("https://example.com/a.ogg")
    end

    test "rejects a non-https URL" do
      assert {:error, "Media URL is invalid"} =
               KaapiSupport.validate_media("http://example.com/a.ogg")
    end
  end

  describe "name/0, mode/0" do
    test "speech_to_text" do
      assert SpeechToText.name() == "speech_to_text"
      assert SpeechToText.mode() == :async
    end

    test "text_to_speech" do
      assert TextToSpeech.name() == "text_to_speech"
      assert TextToSpeech.mode() == :async
    end

    test "filesearch_gpt" do
      assert FilesearchGpt.name() == "filesearch-gpt"
      assert FilesearchGpt.mode() == :async
    end

    test "voice_filesearch_gpt" do
      assert VoiceFilesearchGpt.name() == "voice-filesearch-gpt"
      assert VoiceFilesearchGpt.mode() == :async
    end
  end
end
