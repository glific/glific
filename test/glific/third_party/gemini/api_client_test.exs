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

      result = ApiClient.speech_to_text("3nC0dedAuD10", organization_id)

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

      result = ApiClient.speech_to_text("3nC0dedAuD10", organization_id)

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

      result = ApiClient.speech_to_text("3nC0dedAuD10", organization_id)

      assert result.success == false
      assert result.asr_response_text == 500
    end

    test "handles Tesla error without Tesla.Env", %{organization_id: organization_id} do
      mock(fn %{method: :post} ->
        {:error, :timeout}
      end)

      result = ApiClient.speech_to_text("3nC0dedAuD10", organization_id)

      assert result.success == false
      assert result.asr_response_text == :timeout
    end

    test "handles network timeout error", %{organization_id: organization_id} do
      mock(fn %{method: :post} ->
        {:error, :econnrefused}
      end)

      result = ApiClient.speech_to_text("3nC0dedAuD10", organization_id)

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

      assert %{success: false, asr_response_text: 200} ==
               ApiClient.speech_to_text("3nC0dedAuD10", organization_id)
    end
  end

  describe "text_to_speech/2" do
    test "successfully converts text to speech", %{organization_id: organization_id} do
      # Base64 encoded sample PCM audio data
      sample_audio_data = Base.encode64("fake_pcm_audio_data")

      mock(fn
        %{method: :post, url: url} ->
          assert String.contains?(url, "/gemini-2.5-pro-preview-tts:generateContent")

          %Tesla.Env{
            status: 200,
            body: %{
              candidates: [
                %{
                  content: %{
                    parts: [
                      %{
                        inlineData: %{
                          data: sample_audio_data
                        }
                      }
                    ]
                  }
                }
              ],
              usageMetadata: %{
                promptTokenCount: 50,
                candidatesTokenCount: 100,
                totalTokenCount: 150
              }
            }
          }
      end)

      assert {:ok, "fake_pcm_audio_data"} ==
               ApiClient.text_to_speech("Hello World", organization_id)
    end

    test "handles API error with status code", %{organization_id: organization_id} do
      mock(fn %{method: :post} ->
        %Tesla.Env{
          status: 400,
          body: %{error: "Invalid request"}
        }
      end)

      assert {:error, nil} == ApiClient.text_to_speech("Hello World", organization_id)
    end

    test "handles Tesla error with body", %{organization_id: organization_id} do
      mock(fn %{method: :post} ->
        {:error, %Tesla.Env{body: "Service unavailable"}}
      end)

      assert {:error, nil} == ApiClient.text_to_speech("Hello World", organization_id)
    end

    test "handles Tesla timeout error", %{organization_id: organization_id} do
      mock(fn %{method: :post} ->
        {:error, :timeout}
      end)

      assert {:error, nil} == ApiClient.text_to_speech("Hello World", organization_id)
    end
  end
end
