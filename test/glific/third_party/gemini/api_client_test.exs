defmodule Glific.ThirdParty.Gemini.ApiClientTest do
  use Glific.DataCase
  import Tesla.Mock

  alias Glific.ThirdParty.Gemini.ApiClient

  describe "speech_to_text/2" do
    test "successfully transcribes audio and returns text", %{organization_id: organization_id} do
      mock(fn %{method: :post, url: url} ->
        assert String.contains?(url, "/gemini-2.5-pro:generateContent")

        %Tesla.Env{
          status: 200,
          body: %{
            candidates: [
              %{
                content: %{
                  parts: [
                    %{
                      text: "\"Hello, this is a test message\""
                    }
                  ]
                }
              }
            ],
            usageMetadata: %{
              promptTokenCount: 100,
              candidatesTokenCount: 50,
              totalTokenCount: 150
            }
          }
        }
      end)

      audio_url = "gs://bucket-name/audio-file.ogg"
      result = ApiClient.speech_to_text(audio_url, organization_id)

      assert result.success == true
      assert result.asr_response_text == "Hello, this is a test message"
    end

    test "handles non-200 status code", %{organization_id: organization_id} do
      mock(fn %{method: :post} ->
        %Tesla.Env{
          status: 400,
          body: %{error: "Bad request"}
        }
      end)

      audio_url = "gs://bucket-name/audio-file.ogg"
      result = ApiClient.speech_to_text(audio_url, organization_id)

      assert result.success == false
      assert result.asr_response_text == 400
    end

    test "handles 500 internal server error", %{organization_id: organization_id} do
      mock(fn %{method: :post} ->
        %Tesla.Env{
          status: 500,
          body: %{error: "Internal server error"}
        }
      end)

      audio_url = "gs://bucket-name/audio-file.ogg"
      result = ApiClient.speech_to_text(audio_url, organization_id)

      assert result.success == false
      assert result.asr_response_text == 500
    end

    test "handles Tesla error without Tesla.Env", %{organization_id: organization_id} do
      mock(fn %{method: :post} ->
        {:error, :timeout}
      end)

      audio_url = "gs://bucket-name/audio-file.ogg"
      result = ApiClient.speech_to_text(audio_url, organization_id)

      assert result.success == false
      assert result.asr_response_text == :timeout
    end

    test "handles network timeout error", %{organization_id: organization_id} do
      mock(fn %{method: :post} ->
        {:error, :econnrefused}
      end)

      audio_url = "gs://bucket-name/audio-file.ogg"
      result = ApiClient.speech_to_text(audio_url, organization_id)

      assert result.success == false
      assert result.asr_response_text == :econnrefused
    end

    test "handles response with missing candidates", %{organization_id: organization_id} do
      mock(fn %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            usageMetadata: %{
              promptTokenCount: 100,
              candidatesTokenCount: 0,
              totalTokenCount: 100
            }
          }
        }
      end)

      audio_url = "gs://bucket-name/audio.ogg"

      assert %{success: false, asr_response_text: 200} ==
               ApiClient.speech_to_text(audio_url, organization_id)
    end
  end
end
