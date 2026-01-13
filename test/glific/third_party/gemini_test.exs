defmodule Glific.ThirdParty.GeminiTest do
  use Glific.DataCase
  import Tesla.Mock
  import Mock

  alias Glific.ThirdParty.Gemini

  describe "text_to_speech/2" do
    test "returns error message when GCS is not enabled", %{organization_id: organization_id} do
      result = Gemini.text_to_speech(organization_id, "Hello World")
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
        result = Gemini.do_text_to_speech(organization_id, "Hello World")

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

      result = Gemini.do_text_to_speech(organization_id, "Hello World")

      assert result.success == false
      refute result.media_url
      assert result.translated_text == "Hello World"
    end

    test "handles Tesla error with body", %{organization_id: organization_id} do
      mock(fn %{method: :post} ->
        {:error, %Tesla.Env{body: "Service unavailable"}}
      end)

      result = Gemini.do_text_to_speech(organization_id, "Hello World")

      assert result.success == false
      refute result.media_url
      assert result.translated_text == "Hello World"
    end

    test "handles Tesla timeout error", %{organization_id: organization_id} do
      mock(fn %{method: :post} ->
        {:error, :timeout}
      end)

      result = Gemini.do_text_to_speech(organization_id, "Hello World")

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
        result = Gemini.do_text_to_speech(organization_id, "Hello World")

        assert result.success == false
        refute result.media_url
        assert result.translated_text == "Hello World"
      end
    end
  end
end
