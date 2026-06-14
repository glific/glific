defmodule Glific.Flows.Webhooks.NmtTtsWithBhasiniTest do
  @moduledoc """
  Unit tests for the NmtTtsWithBhasini webhook implementation.

  Tests the module directly via `call/2`, covering:
  - Same source/target language (TTS-only path) with various speech_engine values
  - Different source/target languages (NMT+TTS path) — success and GCS-disabled
  - Unsupported language combinations
  - API failure and unexpected response handling
  """

  use Glific.DataCase, async: false

  import Mock

  alias Glific.Flows.Webhooks.NmtTtsWithBhasini
  alias Glific.Metrics
  alias Glific.OpenAI.ChatGPT
  alias Glific.Partners
  alias Glific.ThirdParty.Gemini

  @ctx %{organization_id: 1}
  @media_url "https://storage.googleapis.com/mock/audio.mp3"

  @success_result %{success: true, media_url: @media_url}
  @failure_result %{success: false, reason: "Gemini error"}

  describe "call/2 - same source and target language (TTS-only)" do
    test "speech_engine == bhashini routes to Gemini TTS" do
      with_mocks([
        {Gemini, [:passthrough], [text_to_speech: fn _org_id, _text -> @success_result end]},
        {ChatGPT, [:passthrough],
         [
           text_to_speech_with_open_ai: fn _org_id, _text ->
             flunk("OpenAI should not be called for bhashini speech_engine")
           end
         ]},
        {Metrics, [:passthrough], [increment: fn _name, _org_id -> :ok end]}
      ]) do
        fields = %{
          "text" => "Hello",
          "source_language" => "Hindi",
          "target_language" => "Hindi",
          "speech_engine" => "bhashini"
        }

        assert {:ok, result} = NmtTtsWithBhasini.call(fields, @ctx)
        assert result.media_url == @media_url
        refute Map.has_key?(result, :success)
      end
    end

    test "speech_engine == open_ai routes to OpenAI TTS" do
      with_mocks([
        {ChatGPT, [:passthrough],
         [text_to_speech_with_open_ai: fn _org_id, _text -> @success_result end]},
        {Gemini, [:passthrough],
         [
           text_to_speech: fn _org_id, _text ->
             flunk("Gemini should not be called for open_ai speech_engine")
           end
         ]}
      ]) do
        fields = %{
          "text" => "Hello",
          "source_language" => "Hindi",
          "target_language" => "Hindi",
          "speech_engine" => "open_ai"
        }

        assert {:ok, result} = NmtTtsWithBhasini.call(fields, @ctx)
        assert result.media_url == @media_url
      end
    end

    test "english language with no speech_engine routes to OpenAI TTS" do
      with_mocks([
        {ChatGPT, [:passthrough],
         [text_to_speech_with_open_ai: fn _org_id, _text -> @success_result end]},
        {Gemini, [:passthrough],
         [
           text_to_speech: fn _org_id, _text ->
             flunk("Gemini should not be called for english language")
           end
         ]}
      ]) do
        fields = %{
          "text" => "Hello",
          "source_language" => "English",
          "target_language" => "English"
        }

        assert {:ok, result} = NmtTtsWithBhasini.call(fields, @ctx)
        assert result.media_url == @media_url
      end
    end

    test "non-english language with no speech_engine routes to Gemini TTS" do
      with_mocks([
        {Gemini, [:passthrough], [text_to_speech: fn _org_id, _text -> @success_result end]},
        {ChatGPT, [:passthrough],
         [
           text_to_speech_with_open_ai: fn _org_id, _text ->
             flunk("OpenAI should not be called for non-english language")
           end
         ]},
        {Metrics, [:passthrough], [increment: fn _name, _org_id -> :ok end]}
      ]) do
        fields = %{
          "text" => "नमस्ते",
          "source_language" => "Hindi",
          "target_language" => "Hindi"
        }

        assert {:ok, result} = NmtTtsWithBhasini.call(fields, @ctx)
        assert result.media_url == @media_url
      end
    end
  end

  describe "call/2 - different source and target (NMT+TTS)" do
    test "returns {:error, 'GCS is disabled'} when org has no GCS services" do
      with_mock(Partners, [:passthrough],
        organization: fn _org_id ->
          %{services: %{}}
        end
      ) do
        fields = %{
          "text" => "Hello",
          "source_language" => "English",
          "target_language" => "Hindi"
        }

        assert {:error, "GCS is disabled"} = NmtTtsWithBhasini.call(fields, @ctx)
      end
    end

    test "returns {:error, 'Language not supported in Gemini'} for unsupported combo" do
      with_mocks([
        {Partners, [:passthrough],
         [
           organization: fn _org_id ->
             %{services: %{"google_cloud_storage" => %{"bucket" => "mock-bucket"}}}
           end
         ]},
        {Gemini, [:passthrough], [valid_language?: fn _src, _tgt -> false end]}
      ]) do
        fields = %{
          "text" => "Hello",
          "source_language" => "Unknown",
          "target_language" => "AlsoUnknown"
        }

        assert {:error, "Language not supported in Gemini"} =
                 NmtTtsWithBhasini.call(fields, @ctx)
      end
    end

    test "returns {:ok, result} on successful NMT+TTS" do
      with_mocks([
        {Partners, [:passthrough],
         [
           organization: fn _org_id ->
             %{services: %{"google_cloud_storage" => %{"bucket" => "mock-bucket"}}}
           end
         ]},
        {Gemini, [:passthrough],
         [
           valid_language?: fn _src, _tgt -> true end,
           nmt_text_to_speech: fn _org_id, _text, _src, _tgt, _opts ->
             %{success: true, media_url: @media_url, translated_text: "नमस्ते"}
           end
         ]},
        {Metrics, [:passthrough], [increment: fn _name, _org_id -> :ok end]}
      ]) do
        fields = %{
          "text" => "Hello",
          "source_language" => "English",
          "target_language" => "Hindi"
        }

        assert {:ok, result} = NmtTtsWithBhasini.call(fields, @ctx)
        assert result.media_url == @media_url
        refute Map.has_key?(result, :success)
      end
    end

    test "returns {:error, reason} when NMT+TTS returns failure" do
      with_mocks([
        {Partners, [:passthrough],
         [
           organization: fn _org_id ->
             %{services: %{"google_cloud_storage" => %{"bucket" => "mock-bucket"}}}
           end
         ]},
        {Gemini, [:passthrough],
         [
           valid_language?: fn _src, _tgt -> true end,
           nmt_text_to_speech: fn _org_id, _text, _src, _tgt, _opts -> @failure_result end
         ]},
        {Metrics, [:passthrough], [increment: fn _name, _org_id -> :ok end]}
      ]) do
        fields = %{
          "text" => "Hello",
          "source_language" => "English",
          "target_language" => "Hindi"
        }

        assert {:error, "Gemini error"} = NmtTtsWithBhasini.call(fields, @ctx)
      end
    end
  end

  describe "call/2 - nil language fields" do
    test "handles nil source_language gracefully" do
      with_mocks([
        {Gemini, [:passthrough], [text_to_speech: fn _org_id, _text -> @success_result end]},
        {Metrics, [:passthrough], [increment: fn _name, _org_id -> :ok end]}
      ]) do
        fields = %{
          "text" => "Hello",
          "source_language" => nil,
          "target_language" => nil
        }

        # Both normalize to "" which are equal, so TTS-only path is taken
        assert {:ok, _result} = NmtTtsWithBhasini.call(fields, @ctx)
      end
    end
  end
end
