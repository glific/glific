defmodule Glific.Flows.Webhooks.AsyncImplementationsTest do
  @moduledoc """
  Contract tests for the four async webhook implementation modules.

  Verifies the behaviour surface that is pure (no Kaapi/HTTP): `name/0` and `mode/0`.
  The worker-phase `call/2` dispatch path is covered in the per-webhook callback tests.
  """
  use Glific.DataCase, async: false

  import Mock

  alias Glific.Flows.Webhooks.Kaapi, as: KaapiSupport
  alias Glific.ThirdParty.Kaapi, as: ThirdPartyKaapi

  alias Glific.Flows.Webhooks.{
    ErrorType,
    FilesearchGpt,
    SpeechToText,
    TextToSpeech,
    VoiceFilesearchGpt
  }

  describe "call/2 self-classifies dispatch failures (error_type on the ack)" do
    # Unparseable organization_id/flow_id/contact_id -> parse_flow_fields returns
    # {:error, :invalid_input, _}, which each node turns into a %{success: false,
    # error_type: :invalid_input} ack (config → notify support) instead of crashing the worker.
    @bad_meta %{"organization_id" => "x", "flow_id" => "y", "contact_id" => "z"}

    test "speech_to_text tags malformed metadata as :invalid_input" do
      fields = Map.put(@bad_meta, "speech", "https://x.test/a.ogg")
      assert %{success: false, error_type: :invalid_input} = SpeechToText.call(fields, %{})
    end

    test "text_to_speech tags malformed metadata as :invalid_input" do
      assert %{success: false, error_type: :invalid_input} =
               TextToSpeech.call(Map.put(@bad_meta, "text", "hi"), %{})
    end

    test "filesearch_gpt tags malformed metadata as :invalid_input" do
      fields = Map.put(@bad_meta, "question", "hi")
      assert %{success: false, error_type: :invalid_input} = FilesearchGpt.call(fields, %{})
    end

    test "voice_filesearch_gpt tags malformed metadata as :invalid_input" do
      assert %{success: false, error_type: :invalid_input} =
               VoiceFilesearchGpt.call(Map.put(@bad_meta, "speech", "x"), %{})
    end

    test "speech_to_text tags an invalid media URL as :invalid_media_url" do
      fields = %{
        "organization_id" => "1",
        "flow_id" => "1",
        "contact_id" => "1",
        "speech" => "not-a-url"
      }

      assert %{success: false, error_type: :invalid_media_url} = SpeechToText.call(fields, %{})
    end

    test "filesearch_gpt tags a missing-Kaapi-creds dispatch failure as :missing_api_key (system)" do
      fields = %{
        "organization_id" => "1",
        "flow_id" => "1",
        "contact_id" => "1",
        "question" => "hi",
        "assistant_id" => "asst_x"
      }

      assert %{success: false, error_type: :missing_api_key, reason: "Kaapi is not active"} =
               FilesearchGpt.call(fields, %{})

      assert ErrorType.class(:missing_api_key) == :system
    end

    test "voice_filesearch_gpt tags a missing-Kaapi-creds dispatch failure as :missing_api_key (system)" do
      fields = %{
        "organization_id" => "1",
        "flow_id" => "1",
        "contact_id" => "1",
        "speech" => "https://x.test/a.ogg"
      }

      assert %{success: false, error_type: :missing_api_key, reason: "Kaapi is not active"} =
               VoiceFilesearchGpt.call(fields, %{})
    end

    # A creds row present but with no usable api_key fails the `when is_binary(api_key)` guard
    # and hits the catch-all: it is NOT "Kaapi is not active", so it fails safe to a generic
    # :unknown rather than claiming a specific cause.
    test "filesearch_gpt fails safe to :unknown when the creds carry no api_key" do
      fields = %{
        "organization_id" => "1",
        "flow_id" => "1",
        "contact_id" => "1",
        "question" => "hi",
        "assistant_id" => "asst_x"
      }

      with_mock ThirdPartyKaapi, [:passthrough], fetch_kaapi_creds: fn _ -> {:ok, %{}} end do
        assert %{
                 success: false,
                 error_type: :unknown,
                 reason: "Unexpected Kaapi dispatch failure"
               } =
                 FilesearchGpt.call(fields, %{})
      end
    end

    test "voice_filesearch_gpt fails safe to :unknown when the creds carry no api_key" do
      fields = %{
        "organization_id" => "1",
        "flow_id" => "1",
        "contact_id" => "1",
        "speech" => "https://x.test/a.ogg"
      }

      with_mock ThirdPartyKaapi, [:passthrough], fetch_kaapi_creds: fn _ -> {:ok, %{}} end do
        assert %{
                 success: false,
                 error_type: :unknown,
                 reason: "Unexpected Kaapi dispatch failure"
               } =
                 VoiceFilesearchGpt.call(fields, %{})
      end
    end
  end

  describe "Kaapi.validate_media/1" do
    test "accepts an https URL" do
      assert :ok = KaapiSupport.validate_media("https://example.com/a.ogg")
    end

    test "rejects a non-https URL as a config error" do
      assert {:error, :invalid_media_url, "Media URL is invalid"} =
               KaapiSupport.validate_media("http://example.com/a.ogg")
    end

    test "rejects a non-binary URL as a config error" do
      assert {:error, :invalid_media_url, _} = KaapiSupport.validate_media(nil)
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
