defmodule Glific.ThirdParty.Kaapi.SttTtsTest do
  use Glific.DataCase
  import Tesla.Mock

  alias Glific.Partners
  alias Glific.ThirdParty.Kaapi

  @org_id 1
  @api_key "sk_test_key"
  @callback_url "https://api.glific.glific.com/webhook/flow_resume"
  @request_metadata %{organization_id: 1, flow_id: 10, contact_id: 5}

  setup do
    {:ok, _credential} =
      Partners.create_credential(%{
        organization_id: @org_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{"api_key" => @api_key},
        is_active: true
      })

    Partners.get_organization!(@org_id) |> Partners.fill_cache()
    :ok
  end

  describe "speech_to_text/5" do
    test "returns success map when Kaapi acknowledges the STT request" do
      mock(fn
        # download audio
        %Tesla.Env{method: :get} ->
          %Tesla.Env{status: 200, body: "fake_audio_bytes"}

        # call_llm
        %Tesla.Env{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{"job_id" => "stt-job-123", "status" => "queued"}
          }
      end)

      result =
        Kaapi.speech_to_text(
          "https://example.com/audio.wav",
          @callback_url,
          @request_metadata,
          @org_id
        )

      assert result.success == true
      assert result["job_id"] == "stt-job-123"
    end

    test "returns error map when audio download fails" do
      mock(fn
        %Tesla.Env{method: :get} ->
          %Tesla.Env{status: 404, body: "Not Found"}
      end)

      result =
        Kaapi.speech_to_text(
          "https://example.com/missing.wav",
          @callback_url,
          @request_metadata,
          @org_id
        )

      assert result.success == false
      assert result.error_type == "download_failed"
      assert result.reason =~ "download"
    end

    test "returns rate_limited error on HTTP 429 from Kaapi" do
      mock(fn
        %Tesla.Env{method: :get} ->
          %Tesla.Env{status: 200, body: "audio_bytes"}

        %Tesla.Env{method: :post} ->
          %Tesla.Env{status: 429, body: %{"error" => "rate limit exceeded"}}
      end)

      result =
        Kaapi.speech_to_text(
          "https://example.com/audio.wav",
          @callback_url,
          @request_metadata,
          @org_id
        )

      assert result.success == false
      assert result.error_type == "rate_limited"
    end

    test "returns timeout error on HTTP 408 from Kaapi" do
      mock(fn
        %Tesla.Env{method: :get} ->
          %Tesla.Env{status: 200, body: "audio"}

        %Tesla.Env{method: :post} ->
          %Tesla.Env{status: 408, body: %{"error" => "request timed out"}}
      end)

      result =
        Kaapi.speech_to_text(
          "https://example.com/audio.wav",
          @callback_url,
          @request_metadata,
          @org_id
        )

      assert result.success == false
      assert result.error_type == "timeout"
    end

    test "returns service_unavailable on HTTP 5xx from Kaapi" do
      mock(fn
        %Tesla.Env{method: :get} ->
          %Tesla.Env{status: 200, body: "audio"}

        %Tesla.Env{method: :post} ->
          %Tesla.Env{status: 503, body: %{"error" => "service unavailable"}}
      end)

      result =
        Kaapi.speech_to_text(
          "https://example.com/audio.wav",
          @callback_url,
          @request_metadata,
          @org_id
        )

      assert result.success == false
      assert result.error_type == "service_unavailable"
    end

    test "applies opts overrides in payload" do
      mock(fn
        %Tesla.Env{method: :get} ->
          %Tesla.Env{status: 200, body: "audio"}

        %Tesla.Env{method: :post, body: body} ->
          decoded = Jason.decode!(body)
          params = get_in(decoded, ["config", "blob", "completion", "params"])
          assert params["model"] == "custom-stt-model"
          assert params["input_language"] == "tamil"

          %Tesla.Env{status: 200, body: %{"job_id" => "stt-456"}}
      end)

      Kaapi.speech_to_text(
        "https://example.com/audio.wav",
        @callback_url,
        @request_metadata,
        @org_id,
        %{model: "custom-stt-model", language: "tamil"}
      )
    end

    test "omits output_language from payload when not specified" do
      mock(fn
        %Tesla.Env{method: :get} ->
          %Tesla.Env{status: 200, body: "audio"}

        %Tesla.Env{method: :post, body: body} ->
          decoded = Jason.decode!(body)
          params = get_in(decoded, ["config", "blob", "completion", "params"])
          refute Map.has_key?(params, "output_language")

          %Tesla.Env{status: 200, body: %{"job_id" => "stt-789"}}
      end)

      Kaapi.speech_to_text(
        "https://example.com/audio.wav",
        @callback_url,
        @request_metadata,
        @org_id
      )
    end

    test "includes output_language in payload when specified" do
      mock(fn
        %Tesla.Env{method: :get} ->
          %Tesla.Env{status: 200, body: "audio"}

        %Tesla.Env{method: :post, body: body} ->
          decoded = Jason.decode!(body)
          params = get_in(decoded, ["config", "blob", "completion", "params"])
          assert params["output_language"] == "hindi"

          %Tesla.Env{status: 200, body: %{"job_id" => "stt-999"}}
      end)

      Kaapi.speech_to_text(
        "https://example.com/audio.wav",
        @callback_url,
        @request_metadata,
        @org_id,
        %{output_language: "hindi"}
      )
    end
  end

  describe "text_to_speech/5" do
    test "returns success map when Kaapi acknowledges the TTS request" do
      mock(fn
        %Tesla.Env{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{"job_id" => "tts-job-abc", "status" => "queued"}
          }
      end)

      result =
        Kaapi.text_to_speech(
          @org_id,
          "Hello, how are you?",
          @callback_url,
          @request_metadata
        )

      assert result.success == true
      assert result["job_id"] == "tts-job-abc"
    end

    test "returns rate_limited error on HTTP 429" do
      mock(fn
        %Tesla.Env{method: :post} ->
          %Tesla.Env{status: 429, body: %{"error" => "rate limited"}}
      end)

      result =
        Kaapi.text_to_speech(@org_id, "Hello", @callback_url, @request_metadata)

      assert result.success == false
      assert result.error_type == "rate_limited"
    end

    test "returns service_unavailable on HTTP 5xx" do
      mock(fn
        %Tesla.Env{method: :post} ->
          %Tesla.Env{status: 500, body: %{"error" => "internal server error"}}
      end)

      result =
        Kaapi.text_to_speech(@org_id, "Hello", @callback_url, @request_metadata)

      assert result.success == false
      assert result.error_type == "service_unavailable"
    end

    test "applies opts overrides in payload" do
      mock(fn
        %Tesla.Env{method: :post, body: body} ->
          decoded = Jason.decode!(body)
          params = get_in(decoded, ["config", "blob", "completion", "params"])
          assert params["voice"] == "custom-voice"
          assert params["language"] == "english"
          assert params["model"] == "custom-tts-model"

          %Tesla.Env{status: 200, body: %{"job_id" => "tts-789"}}
      end)

      Kaapi.text_to_speech(
        @org_id,
        "Hello",
        @callback_url,
        @request_metadata,
        %{voice: "custom-voice", language: "english", model: "custom-tts-model"}
      )
    end

    test "returns timeout error on transport :timeout from Kaapi" do
      mock(fn
        %Tesla.Env{method: :post} -> {:error, :timeout}
      end)

      result =
        Kaapi.text_to_speech(@org_id, "Hello", @callback_url, @request_metadata)

      assert result.success == false
      assert result.error_type == "timeout"
    end
  end
end
