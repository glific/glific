defmodule Glific.ThirdParty.GeminiTest do
  use Glific.DataCase
  import Tesla.Mock
  import Mock

  alias Glific.ThirdParty.Gemini

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
      result = Gemini.speech_to_text(audio_url, organization_id)

      assert result.success == true
      assert result.asr_response_text == "Hello, this is a test message"
    end

    test "handles errors", %{organization_id: organization_id} do
      mock(fn %{method: :post} ->
        %Tesla.Env{
          status: 400,
          body: %{error: "Bad request"}
        }
      end)

      audio_url = "gs://bucket-name/audio-file.ogg"
      result = Gemini.speech_to_text(audio_url, organization_id)

      assert result.success == false
      assert result.asr_response_text == 400
    end
  end

  describe "text_to_speech/2" do
    test "returns error message when GCS is not enabled", %{organization_id: organization_id} do
      result = Gemini.text_to_speech(organization_id, "Hello World")
      assert result == "Enable GCS to use Gemini text to speech"
    end

    @tag :skip
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

    @tag :skip
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

  describe "nmt_text_to_speech/5" do
    @tag :skip
    test "successfully translates and converts to speech with Gemini engine", %{
      organization_id: organization_id
    } do
      sample_audio_data = Base.encode64("fake_pcm_audio_data")

      mock_global(fn env ->
        cond do
          env.url == "https://translation.googleapis.com/language/translate/v2" ->
            %Tesla.Env{
              status: 200,
              body: %{
                "data" => %{
                  "translations" => [
                    %{"translatedText" => "नमस्ते"}
                  ]
                }
              }
            }

          true ->
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
        end
      end)

      with_mock Glific.GCS.GcsWorker,
        upload_media: fn _file, _remote_name, _org_id ->
          {:ok,
           %{
             url: "https://storage.googleapis.com/bucket/Gemini/outbound/test.mp3"
           }}
        end do
        result =
          Gemini.nmt_text_to_speech(organization_id, "Hello", "english", "hindi",
            speech_engine: "gemini"
          )

        assert true == result.success

        assert "https://storage.googleapis.com/bucket/Gemini/outbound/test.mp3" ==
                 result.media_url

        assert "नमस्ते" == result.translated_text
      end
    end

    @tag :skip
    test "successfully translates and converts to speech with OpenAI engine", %{
      organization_id: organization_id
    } do
      Glific.Partners.create_credential(%{
        shortcode: "google_cloud_storage",
        organization_id: organization_id,
        is_active: true
      })

      sample_audio_data = Base.encode64("fake_pcm_audio_data")

      mock_global(fn env ->
        cond do
          env.url == "https://translation.googleapis.com/language/translate/v2" ->
            %Tesla.Env{
              status: 200,
              body: %{
                "data" => %{
                  "translations" => [
                    %{"translatedText" => "Hola"}
                  ]
                }
              }
            }

          true ->
            %Tesla.Env{
              status: 200,
              body: sample_audio_data
            }
        end
      end)

      with_mock Glific.GCS.GcsWorker,
        upload_media: fn _file, _remote_name, _org_id ->
          {:ok,
           %{
             url: "https://storage.googleapis.com/bucket/Gemini/outbound/test.mp3"
           }}
        end do
        result =
          Gemini.nmt_text_to_speech(organization_id, "Hello", "english", "spanish",
            speech_engine: "open_ai"
          )

        assert true == result.success

        assert "https://storage.googleapis.com/bucket/Gemini/outbound/test.mp3" ==
                 result.media_url

        assert "Hola" == result.translated_text
      end
    end

    test "handles Google Translate API failure", %{organization_id: organization_id} do
      mock_global(fn %Tesla.Env{url: "https://translation.googleapis.com/language/translate/v2"} ->
        %Tesla.Env{status: 500, body: %{"error" => "Service Unavailable"}}
      end)

      result =
        Gemini.nmt_text_to_speech(organization_id, "Hello", "english", "hindi", [])

      assert result.success == false
      assert result.media_url == nil
      assert result.translated_text == "Hello"
    end

    @tag :skip
    test "handles errors when token size exceeds 300", %{organization_id: organization_id} do
      sample_audio_data = Base.encode64("fake_pcm_audio_data")
      # Token size is 319
      long_text =
        String.duplicate(
          "This test is to verifies that the Gemini NMT text-to-speech functionality can't handle longer text inputs that crosses the token limit.",
          11
        )

      mock_global(fn env ->
        cond do
          env.url == "https://translation.googleapis.com/language/translate/v2" ->
            # This verifies that the token size exceeds the limit
            assert %{"q" => "translation not available for long messages"} =
                     Jason.decode!(env.body)

            %Tesla.Env{
              status: 200,
              body: %{
                "data" => %{
                  "translations" => [
                    %{"translatedText" => "लंबे संदेशों के लिए अनुवाद उपलब्ध नहीं है"}
                  ]
                }
              }
            }

          true ->
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
        end
      end)

      with_mock Glific.GCS.GcsWorker,
        upload_media: fn _file, _remote_name, _org_id ->
          {:ok,
           %{
             url: "https://storage.googleapis.com/bucket/Gemini/outbound/test.mp3"
           }}
        end do
        result =
          Gemini.nmt_text_to_speech(organization_id, long_text, "english", "hindi", [])

        assert true == result.success

        assert "https://storage.googleapis.com/bucket/Gemini/outbound/test.mp3" ==
                 result.media_url

        assert "लंबे संदेशों के लिए अनुवाद उपलब्ध नहीं है" == result.translated_text
      end
    end

    test "handles TTS failure after successful translation", %{
      organization_id: organization_id
    } do
      mock_global(fn env ->
        cond do
          env.url == "https://translation.googleapis.com/language/translate/v2" ->
            %Tesla.Env{
              status: 200,
              body: %{
                "data" => %{
                  "translations" => [
                    %{"translatedText" => "नमस्ते"}
                  ]
                }
              }
            }

          true ->
            %Tesla.Env{
              status: 400,
              body: %{error: "Invalid request"}
            }
        end
      end)

      result =
        Gemini.nmt_text_to_speech(organization_id, "Hello", "english", "hindi", [])

      assert result.success == false
      assert result.media_url == nil
      assert result.translated_text == "Hello"
    end

    test "handles OpenAI TTS failure after successful translation", %{
      organization_id: organization_id
    } do
      mock_global(fn env ->
        cond do
          env.url == "https://translation.googleapis.com/language/translate/v2" ->
            %Tesla.Env{
              status: 200,
              body: %{
                "data" => %{
                  "translations" => [
                    %{"translatedText" => "नमस्ते"}
                  ]
                }
              }
            }

          true ->
            %Tesla.Env{
              status: 400,
              body: %{error: "Invalid request"}
            }
        end
      end)

      result =
        Gemini.nmt_text_to_speech(organization_id, "Hello", "english", "spanish",
          speech_engine: "open_ai"
        )

      assert result.success == false
      assert result.media_url == nil
      assert result.translated_text == "Hello"
    end

    @tag :skip
    test "uses gemini engine by default when speech_engine option is not provided", %{
      organization_id: organization_id
    } do
      sample_audio_data = Base.encode64("fake_pcm_audio_data")

      mock_global(fn env ->
        cond do
          env.url == "https://translation.googleapis.com/language/translate/v2" ->
            %Tesla.Env{
              status: 200,
              body: %{
                "data" => %{
                  "translations" => [
                    %{"translatedText" => "नमस्ते"}
                  ]
                }
              }
            }

          String.contains?(env.url, "https://generativelanguage.googleapis.com/v1beta/models") ->
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
        end
      end)

      with_mock Glific.GCS.GcsWorker,
        upload_media: fn _file, _remote_name, _org_id ->
          {:ok, %{url: "https://storage.googleapis.com/bucket/test.mp3"}}
        end do
        result =
          Gemini.nmt_text_to_speech(organization_id, "Hello", "english", "hindi", [])

        assert result.success == true
      end
    end
  end

  @tag :skip
  test "uses gemini engine by default when any unsupported speech_engine option is provided", %{
    organization_id: organization_id
  } do
    sample_audio_data = Base.encode64("fake_pcm_audio_data")

    mock_global(fn env ->
      cond do
        env.url == "https://translation.googleapis.com/language/translate/v2" ->
          %Tesla.Env{
            status: 200,
            body: %{
              "data" => %{
                "translations" => [
                  %{"translatedText" => "नमस्ते"}
                ]
              }
            }
          }

        String.contains?(env.url, "https://generativelanguage.googleapis.com/v1beta/models") ->
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
      end
    end)

    with_mock Glific.GCS.GcsWorker,
      upload_media: fn _file, _remote_name, _org_id ->
        {:ok, %{url: "https://storage.googleapis.com/bucket/test.mp3"}}
      end do
      result =
        Gemini.nmt_text_to_speech(organization_id, "Hello", "english", "hindi",
          speech_engine: "bhashini"
        )

      assert result.success == true
    end
  end

  describe "valid_language?/2" do
    test "returns true for supported language pairs" do
      assert Gemini.valid_language?("english", "hindi") == true
      assert Gemini.valid_language?("tamil", "telugu") == true
      assert Gemini.valid_language?("spanish", "bengali") == true
      assert Gemini.valid_language?("marathi", "english") == true
    end

    test "returns false when source language is not supported" do
      assert Gemini.valid_language?("french", "hindi") == false
      assert Gemini.valid_language?("german", "english") == false
    end

    test "returns false when target language is not supported" do
      assert Gemini.valid_language?("english", "french") == false
      assert Gemini.valid_language?("hindi", "japanese") == false
    end

    test "returns false when both languages are not supported" do
      assert Gemini.valid_language?("french", "german") == false
      assert Gemini.valid_language?("japanese", "chinese") == false
    end
  end
end
