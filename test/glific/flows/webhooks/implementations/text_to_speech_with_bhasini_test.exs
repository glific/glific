defmodule Glific.Flows.Webhooks.TextToSpeechWithBhasiniTest do
  @moduledoc """
  Unit tests for the TextToSpeechWithBhasini webhook implementation.

  Tests the module directly via `call/2`, mocking Contacts.preload_contact_language/1,
  ChatGPT.text_to_speech_with_open_ai/2, and Gemini.text_to_speech/2 to cover:
  - speech_engine == "open_ai" → OpenAI
  - speech_engine == "bhashini" → Gemini
  - English language contact → OpenAI
  - Non-English language contact → Gemini
  - API failure paths
  """

  use Glific.DataCase, async: false

  import Mock

  alias Glific.Contacts
  alias Glific.Contacts.Contact
  alias Glific.Flows.Webhooks.TextToSpeechWithBhasini
  alias Glific.OpenAI.ChatGPT
  alias Glific.Settings.Language
  alias Glific.ThirdParty.Gemini

  @ctx %{organization_id: 1}

  defp english_contact(id) do
    %Contact{id: id, organization_id: 1, language: %Language{label: "English"}}
  end

  defp hindi_contact(id) do
    %Contact{id: id, organization_id: 1, language: %Language{label: "Hindi"}}
  end

  defp base_fields(contact_id, overrides \\ %{}) do
    Map.merge(
      %{
        "text" => "Hello, world!",
        "contact" => %{"id" => to_string(contact_id)}
      },
      overrides
    )
  end

  @success_tts_result %{success: true, media_url: "https://example.com/audio.mp3"}
  @failure_tts_result %{success: false, reason: "TTS failed upstream"}

  describe "call/2 - speech_engine == open_ai" do
    test "routes to OpenAI regardless of language" do
      with_mocks([
        {Contacts, [:passthrough], [preload_contact_language: fn _id -> hindi_contact(1) end]},
        {ChatGPT, [:passthrough],
         [text_to_speech_with_open_ai: fn _org_id, _text -> @success_tts_result end]},
        {Gemini, [:passthrough],
         [
           text_to_speech: fn _org_id, _text ->
             flunk("Gemini should not be called when speech_engine is open_ai")
           end
         ]}
      ]) do
        fields = base_fields(1, %{"speech_engine" => "open_ai"})
        assert {:ok, result} = TextToSpeechWithBhasini.call(fields, @ctx)
        assert result.media_url == "https://example.com/audio.mp3"
        refute Map.has_key?(result, :success)
      end
    end
  end

  describe "call/2 - speech_engine == bhashini" do
    test "routes to Gemini regardless of language" do
      with_mocks([
        {Contacts, [:passthrough], [preload_contact_language: fn _id -> english_contact(1) end]},
        {Gemini, [:passthrough], [text_to_speech: fn _org_id, _text -> @success_tts_result end]},
        {ChatGPT, [:passthrough],
         [
           text_to_speech_with_open_ai: fn _org_id, _text ->
             flunk("OpenAI should not be called when speech_engine is bhashini")
           end
         ]}
      ]) do
        fields = base_fields(1, %{"speech_engine" => "bhashini"})
        assert {:ok, result} = TextToSpeechWithBhasini.call(fields, @ctx)
        assert result.media_url == "https://example.com/audio.mp3"
      end
    end
  end

  describe "call/2 - language-based routing" do
    test "English contact with no speech_engine routes to OpenAI" do
      with_mocks([
        {Contacts, [:passthrough], [preload_contact_language: fn _id -> english_contact(1) end]},
        {ChatGPT, [:passthrough],
         [text_to_speech_with_open_ai: fn _org_id, _text -> @success_tts_result end]},
        {Gemini, [:passthrough],
         [
           text_to_speech: fn _org_id, _text ->
             flunk("Gemini should not be called for English contact")
           end
         ]}
      ]) do
        fields = base_fields(1)
        assert {:ok, _result} = TextToSpeechWithBhasini.call(fields, @ctx)
      end
    end

    test "non-English contact with no speech_engine routes to Gemini" do
      with_mocks([
        {Contacts, [:passthrough], [preload_contact_language: fn _id -> hindi_contact(1) end]},
        {Gemini, [:passthrough], [text_to_speech: fn _org_id, _text -> @success_tts_result end]},
        {ChatGPT, [:passthrough],
         [
           text_to_speech_with_open_ai: fn _org_id, _text ->
             flunk("OpenAI should not be called for non-English contact")
           end
         ]}
      ]) do
        fields = base_fields(1)
        assert {:ok, result} = TextToSpeechWithBhasini.call(fields, @ctx)
        assert result.media_url == "https://example.com/audio.mp3"
      end
    end
  end

  describe "call/2 - TTS API failure" do
    test "returns {:error, message} when TTS returns success: false with reason" do
      with_mocks([
        {Contacts, [:passthrough], [preload_contact_language: fn _id -> english_contact(1) end]},
        {ChatGPT, [:passthrough],
         [text_to_speech_with_open_ai: fn _org_id, _text -> @failure_tts_result end]}
      ]) do
        fields = base_fields(1)
        assert {:error, msg} = TextToSpeechWithBhasini.call(fields, @ctx)
        assert msg == "TTS failed upstream"
      end
    end

    test "returns {:error, message} when TTS returns success: false without reason" do
      with_mocks([
        {Contacts, [:passthrough], [preload_contact_language: fn _id -> english_contact(1) end]},
        {ChatGPT, [:passthrough],
         [
           text_to_speech_with_open_ai: fn _org_id, _text ->
             %{success: false}
           end
         ]}
      ]) do
        fields = base_fields(1)
        assert {:error, msg} = TextToSpeechWithBhasini.call(fields, @ctx)
        assert msg =~ "Text to speech failed"
      end
    end

    test "returns {:error, message} on unexpected response" do
      with_mocks([
        {Contacts, [:passthrough], [preload_contact_language: fn _id -> english_contact(1) end]},
        {ChatGPT, [:passthrough],
         [text_to_speech_with_open_ai: fn _org_id, _text -> "unexpected" end]}
      ]) do
        fields = base_fields(1)
        assert {:error, msg} = TextToSpeechWithBhasini.call(fields, @ctx)
        assert msg =~ "Unexpected response"
      end
    end
  end
end
