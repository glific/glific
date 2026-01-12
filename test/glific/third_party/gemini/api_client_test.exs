defmodule Glific.ThirdParty.Gemini.ApiClientTest do
  use Glific.DataCase
  import Tesla.Mock
  import Mock

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

  describe "text_to_speech/2" do
    test "returns error message when GCS is not enabled", %{organization_id: organization_id} do
      result = ApiClient.text_to_speech(organization_id, "Hello World")
      assert result == "Enable GCS is use Gemini text to speech"
    end

    test "successfully converts text to speech with GCS enabled", %{
      organization_id: organization_id
    } do
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

      with_mock Glific.GCS.GcsWorker,
        upload_media: fn _file, _remote_name, _org_id ->
          {:ok,
           %{
             url: "https://storage.googleapis.com/bucket/Gemini/outbound/test.mp3"
           }}
        end do
        result = ApiClient.do_text_to_speech(organization_id, "Hello World")

        assert result.success == true

        assert result.media_url ==
                 "https://storage.googleapis.com/bucket/Gemini/outbound/test.mp3"

        assert result.translated_text == "Hello World"
      end
    end

    test "handles API error with status code", %{organization_id: organization_id} do
      mock(fn %{method: :post} ->
        %Tesla.Env{
          status: 400,
          body: %{error: "Invalid request"}
        }
      end)

      result = ApiClient.do_text_to_speech(organization_id, "Hello World")

      assert result.success == false
      refute result.media_url
      assert result.translated_text == "Hello World"
    end

    test "handles Tesla error with body", %{organization_id: organization_id} do
      mock(fn %{method: :post} ->
        {:error, %Tesla.Env{body: "Service unavailable"}}
      end)

      result = ApiClient.do_text_to_speech(organization_id, "Hello World")

      assert result.success == false
      refute result.media_url
      assert result.translated_text == "Hello World"
    end

    test "handles Tesla timeout error", %{organization_id: organization_id} do
      mock(fn %{method: :post} ->
        {:error, :timeout}
      end)

      result = ApiClient.do_text_to_speech(organization_id, "Hello World")

      assert result.success == false
      refute result.media_url
      assert result.translated_text == "Hello World"
    end

    test "handles GCS upload failure", %{organization_id: organization_id} do
      sample_audio_data = Base.encode64("fake_pcm_audio_data")

      mock(fn %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            candidates: [
              %{
                content: %{
                  parts: [
                    %{
                      inlineData: %{
                        data: sample_audio_data,
                        mimeType: "audio/pcm"
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

      with_mock Glific.GCS.GcsWorker,
        upload_media: fn _file, _remote_name, _org_id ->
          {:error, "Upload failed"}
        end do
        result = ApiClient.do_text_to_speech(organization_id, "Hello World")

        assert result.success == false
        refute result.media_url
        assert result.translated_text == "Hello World"
      end
    end
  end
end
