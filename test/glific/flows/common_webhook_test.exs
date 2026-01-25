defmodule Glific.Flows.CommonWebhookTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    Certificates.CertificateTemplate,
    Clients.CommonWebhook,
    Fixtures,
    Messages,
    Partners,
    Partners.Provider,
    Seeds.SeedsDev,
    ThirdParty.GoogleSlide.Slide
  }

  import Mock

  doctest Slide
  doctest Glific
  doctest Provider

  @mock_presentation_id "copied_presentation123"
  @mock_copied_slide %{"id" => @mock_presentation_id}
  @mock_thumbnail %{"contentUrl" => "image_url"}

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)

    valid_attrs = %{
      shortcode: "google_cloud_storage",
      secrets: %{
        "bucket" => "mock-bucket-name",
        "service_account" =>
          Jason.encode!(%{
            project_id: "DEFAULT PROJECT ID",
            private_key_id: "DEFAULT API KEY",
            client_email: "DEFAULT CLIENT EMAIL",
            private_key: "DEFAULT PRIVATE KEY"
          })
      },
      is_active: true,
      organization_id: 1
    }

    valid_attrs_slides = %{
      shortcode: "google_slides",
      secrets: %{
        "service_account" =>
          Jason.encode!(%{
            project_id: "DEFAULT PROJECT ID",
            private_key_id: "DEFAULT API KEY",
            client_email: "DEFAULT CLIENT EMAIL",
            private_key: "DEFAULT PRIVATE KEY"
          })
      },
      is_active: true,
      organization_id: 1
    }

    {:ok, _credential} = Partners.create_credential(valid_attrs)
    {:ok, _credential} = Partners.create_credential(valid_attrs_slides)
    :ok
  end

  test "successful geolocation response" do
    lat = "37.7749"
    long = "-122.4194"
    fields = %{"lat" => lat, "long" => long}

    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "results" => [
                %{
                  "address_components" => [
                    %{"long_name" => "San Francisco", "types" => ["locality"]},
                    %{"long_name" => "CA", "types" => ["administrative_area_level_1"]},
                    %{"long_name" => "USA", "types" => ["country"]}
                  ],
                  "formatted_address" => "San Francisco, CA, USA"
                }
              ]
            })
        }
    end)

    result = CommonWebhook.webhook("geolocation", fields)

    assert result[:success] == true
    assert result[:city] == "San Francisco"
    assert result[:state] == "CA"
    assert result[:country] == "USA"
    assert result[:postal_code] == "N/A"
    assert result[:district] == "N/A"
    assert result[:address] == "San Francisco, CA, USA"
  end

  test "geolocation failure response" do
    lat = "37.7749"
    long = "-122.4194"
    fields = %{"lat" => lat, "long" => long}

    # Mock a non-200 response from the API (e.g., 500 Internal Server Error)
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 500,
          body: "Internal Server Error"
        }
    end)

    result = CommonWebhook.webhook("geolocation", fields)

    # Assert that success is false and an error message is returned
    refute result[:success]
    refute is_nil(result[:error])
    assert result[:error] == "Received status code 500"
  end

  test "detect_language/1 detects correct language from voice note using Bhashini" do
    fields = %{
      "speech" =>
        "https://filemanager.gupshup.io/wa/69d27dd2-46d2-4872-b18e-f6aeeb2ec64d/wa/media/8656858131106230?download=false"
    }

    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body:
            "{\"taskType\":\"audio-lang-detection\",\"output\":[{\"audio\":{\"audioContent\":null,\"audioUri\":\"https://filemanager.gupshup.io/wa/69d27dd2-46d2-4872-b18e-f6aeeb2ec64d/wa/media/8656858131106230?download=false\"},\"langPrediction\":[{\"langCode\":\"en\",\"scriptCode\":null,\"langScore\":null}]}],\"config\":null}"
        }
    end)

    result = CommonWebhook.webhook("detect_language", fields)
    assert result[:success] == true
    assert result[:detected_language] == "English"
  end

  test "detect_language/1 throws error when error from Bhashini" do
    fields = %{
      "speech" =>
        "https://filemanager.gupshup.io/wa/69d27dd2-46d2-4872-b18e-f6aeeb2ec64d/wa/media/8656858131106230?download=false"
    }

    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 500,
          body: "Internal Server Error"
        }
    end)

    result = CommonWebhook.webhook("detect_language", fields)
    assert result[:success] == false
    assert result[:detected_language] == "Could not detect language"
  end

  test "parse_via_gpt_vision without response_format params, trying to get valid json" do
    with_mock(
      Messages,
      validate_media: fn _, _ -> %{is_valid: true, message: "success"} end
    ) do
      Tesla.Mock.mock(fn
        %{url: "https://api.openai.com/v1/chat/completions"} ->
          %Tesla.Env{
            status: 200,
            body: %{
              "choices" => [
                %{
                  "message" => %{
                    "content" => "```json\n{\n  \"steps\": 4,\n  \"answer\": 10\n}\n```"
                  }
                }
              ]
            }
          }
      end)

      fields = %{
        "prompt" =>
          "ignore the image, value of steps is 4 and value of answer is 10, give in valid json",
        "url" =>
          "https://fastly.picsum.photos/id/145/200/300.jpg?hmac=mIsOtHDzbaNzDdNRa6aQCd5CHCVewrkTO5B1D4aHMB8",
        "model" => "gpt-4o"
      }

      assert %{success: true, response: "```json\n{\n  \"steps\": 4,\n  \"answer\": 10\n}\n```"} =
               CommonWebhook.webhook("parse_via_gpt_vision", fields)
    end
  end

  test "parse_via_gpt_vision with response_format params type json_object, trying to get valid json" do
    with_mock(
      Messages,
      validate_media: fn _, _ -> %{is_valid: true, message: "success"} end
    ) do
      Tesla.Mock.mock(fn
        %{url: "https://api.openai.com/v1/chat/completions"} ->
          %Tesla.Env{
            status: 200,
            body: %{
              "choices" => [
                %{
                  "message" => %{
                    "content" => "{\n  \"steps\": 4,\n  \"answer\": 10\n}"
                  }
                }
              ]
            }
          }
      end)

      fields = %{
        "prompt" =>
          "ignore the image, value of steps is 4 and value of answer is 10, give in valid json",
        "url" =>
          "https://fastly.picsum.photos/id/145/200/300.jpg?hmac=mIsOtHDzbaNzDdNRa6aQCd5CHCVewrkTO5B1D4aHMB8",
        "model" => "gpt-4o",
        "response_format" => %{"type" => "json_object"}
      }

      assert %{success: true, response: %{"steps" => 4, "answer" => 10}} =
               CommonWebhook.webhook("parse_via_gpt_vision", fields)
    end
  end

  test "parse_via_gpt_vision with invalid response_format param, trying to get valid json" do
    with_mock(
      Messages,
      validate_media: fn _, _ -> %{is_valid: true, message: "success"} end
    ) do
      Tesla.Mock.mock(fn
        %{url: "https://api.openai.com/v1/chat/completions"} ->
          %Tesla.Env{
            status: 200,
            body: %{
              "choices" => [
                %{
                  "message" => %{
                    "content" => "{\n  \"steps\": 4,\n  \"answer\": 10\n}"
                  }
                }
              ]
            }
          }
      end)

      fields = %{
        "prompt" =>
          "ignore the image, value of steps is 4 and value of answer is 10, give in valid json",
        "url" =>
          "https://fastly.picsum.photos/id/145/200/300.jpg?hmac=mIsOtHDzbaNzDdNRa6aQCd5CHCVewrkTO5B1D4aHMB8",
        "model" => "gpt-4o",
        # the response format is invalid
        "response_format" => %{"type" => "json_objectz"}
      }

      assert "response_format type should be json_schema or json_object" =
               CommonWebhook.webhook("parse_via_gpt_vision", fields)
    end
  end

  test "parse_via_gpt_vision with response_format param as json_schema, trying to get valid json" do
    with_mock(
      Messages,
      validate_media: fn _, _ -> %{is_valid: true, message: "success"} end
    ) do
      Tesla.Mock.mock(fn
        %{url: "https://api.openai.com/v1/chat/completions"} ->
          %Tesla.Env{
            status: 200,
            body: %{
              "choices" => [
                %{
                  "message" => %{
                    "content" => "{\n  \"steps\": \"4\",\n  \"answer\": \"10\"\n}"
                  }
                }
              ]
            }
          }
      end)

      fields = %{
        "prompt" =>
          "ignore the image, value of steps is 4 and value of answer is 10, give in valid json",
        "url" =>
          "https://fastly.picsum.photos/id/145/200/300.jpg?hmac=mIsOtHDzbaNzDdNRa6aQCd5CHCVewrkTO5B1D4aHMB8",
        "model" => "gpt-4o",
        "response_format" => %{
          "type" => "json_schema",
          "json_schema" => %{
            "name" => "schemaing",
            "strict" => true,
            "schema" => %{
              "type" => "object",
              "properties" => %{
                "steps" => %{
                  "type" => "string"
                },
                "answer" => %{
                  "type" => "string"
                }
              },
              "required" => [
                "steps",
                "answer"
              ],
              "additionalProperties" => false
            }
          }
        }
      }

      assert %{success: true, response: %{"steps" => "4", "answer" => "10"}} =
               CommonWebhook.webhook("parse_via_gpt_vision", fields)
    end
  end

  test "parse_via_gpt_vision with response_format param as json_schema, but got a non-nil refusal" do
    with_mock(
      Messages,
      validate_media: fn _, _ -> %{is_valid: true, message: "success"} end
    ) do
      Tesla.Mock.mock(fn
        %{url: "https://api.openai.com/v1/chat/completions"} ->
          %Tesla.Env{
            status: 200,
            body: %{
              "choices" => [
                %{
                  "message" => %{
                    "content" => nil,
                    "refusal" =>
                      "I'm sorry, but I can't provide the information from the document."
                  }
                }
              ]
            }
          }
      end)

      fields = %{
        "prompt" =>
          "ignore the image, value of steps is 4 and value of answer is 10, give in valid json",
        "url" =>
          "https://fastly.picsum.photos/id/145/200/300.jpg?hmac=mIsOtHDzbaNzDdNRa6aQCd5CHCVewrkTO5B1D4aHMB8",
        "model" => "gpt-4o",
        "response_format" => %{
          "type" => "json_schema",
          "json_schema" => %{
            "name" => "schemaing",
            "strict" => true,
            "schema" => %{
              "type" => "object",
              "properties" => %{
                "steps" => %{
                  "type" => "string"
                },
                "answer" => %{
                  "type" => "string"
                }
              },
              "required" => [
                "steps",
                "answer"
              ],
              "additionalProperties" => false
            }
          }
        }
      }

      assert "I'm sorry, but I can't provide the information from the document." =
               CommonWebhook.webhook("parse_via_gpt_vision", fields)
    end
  end

  test "parse_via_gpt_vision with response_format param as invalid json_schema, trying to get valid json" do
    with_mock(
      Messages,
      validate_media: fn _, _ -> %{is_valid: true, message: "success"} end
    ) do
      Tesla.Mock.mock(fn
        %{url: "https://api.openai.com/v1/chat/completions"} ->
          %Tesla.Env{
            status: 400,
            body: %{
              "error" => %{
                "message" =>
                  "Invalid schema for response_format 'schemaing': In context=(), 'additionalProperties' is required to be supplied and to be false."
              }
            }
          }
      end)

      fields = %{
        "prompt" =>
          "ignore the image, value of steps is 4 and value of answer is 10, give in valid json",
        "url" =>
          "https://fastly.picsum.photos/id/145/200/300.jpg?hmac=mIsOtHDzbaNzDdNRa6aQCd5CHCVewrkTO5B1D4aHMB8",
        "model" => "gpt-4o",
        "response_format" => %{
          "type" => "json_schema",
          "json_schema" => %{
            "name" => "schemaing",
            "strict" => true,
            "schema" => %{
              "type" => "object",
              "properties" => %{
                "steps" => %{
                  "type" => "string"
                },
                "answer" => %{
                  "type" => "string"
                }
              },
              "required" => [
                "steps",
                "answer"
              ]
              # additionalProperties is mandatory
              # "additionalProperties" => false
            }
          }
        }
      }

      assert "Invalid schema for response_format" <> _ =
               CommonWebhook.webhook("parse_via_gpt_vision", fields)
    end
  end

  test "parse_via_chat_gpt, failed due to empty question_text" do
    assert %{success: false, parsed_msg: "question_text is empty"} =
             CommonWebhook.webhook("parse_via_chat_gpt", %{})
  end

  test "parse_via_chat_gpt, failed due to empty question_text: 2" do
    fields = %{
      "question_text" => ""
    }

    assert %{success: false, parsed_msg: "question_text is empty"} =
             CommonWebhook.webhook("parse_via_chat_gpt", fields)
  end

  test "parse_via_chat_gpt, success with only question_text as params, rest will be defaults" do
    fields = %{
      "question_text" => "get first 10 numbers and their squares, only return min and max"
    }

    Tesla.Mock.mock(fn
      %{url: "https://api.openai.com/v1/chat/completions"} ->
        %Tesla.Env{
          status: 200,
          body: %{
            "choices" => [
              %{
                "message" => %{
                  "content" =>
                    "1^2 = 1\n2^2 = 4\n3^2 = 9\n4^2 = 16\n5^2 = 25\n6^2 = 36\n7^2 = 49\n8^2 = 64\n9^2 = 81\n10^2 = 100\n\nMin: 1\nMax: 100"
                }
              }
            ]
          }
        }
    end)

    assert %{
             success: true,
             parsed_msg:
               "1^2 = 1\n2^2 = 4\n3^2 = 9\n4^2 = 16\n5^2 = 25\n6^2 = 36\n7^2 = 49\n8^2 = 64\n9^2 = 81\n10^2 = 100\n\nMin: 1\nMax: 100"
           } =
             CommonWebhook.webhook("parse_via_chat_gpt", fields)
  end

  test "parse_via_chat_gpt, success with response_format as json_object" do
    fields = %{
      "question_text" =>
        "get first 10 numbers and their squares, only return min and max in json",
      "response_format" => %{"type" => "json_object"}
    }

    Tesla.Mock.mock(fn
      %{url: "https://api.openai.com/v1/chat/completions"} ->
        %Tesla.Env{
          status: 200,
          body: %{
            "choices" => [
              %{
                "message" => %{
                  "content" =>
                    "{\n  \"min\": {\n    \"number\": 1,\n    \"square\": 1\n  },\n  \"max\": {\n    \"number\": 10,\n    \"square\": 100\n  }\n}"
                }
              }
            ]
          }
        }
    end)

    assert %{
             success: true,
             parsed_msg: %{
               "min" => %{
                 "square" => 1,
                 "number" => 1
               },
               "max" => %{
                 "square" => 100,
                 "number" => 10
               }
             }
           } =
             CommonWebhook.webhook("parse_via_chat_gpt", fields)
  end

  test "parse_via_chat_gpt, success with response_format as json_schema" do
    fields = %{
      "question_text" =>
        "get first 10 numbers and their squares, only return min and max in json",
      "response_format" => %{
        "type" => "json_schema",
        "json_schema" => %{
          "name" => "square_schema",
          "strict" => true,
          "schema" => %{
            "type" => "object",
            "properties" => %{
              "minimum value" => %{
                "type" => "string"
              },
              "maximum_value" => %{
                "type" => "string"
              }
            },
            "required" => [
              "minimum value",
              "maximum_value"
            ],
            "additionalProperties" => false
          }
        }
      }
    }

    Tesla.Mock.mock(fn
      %{url: "https://api.openai.com/v1/chat/completions"} ->
        %Tesla.Env{
          status: 200,
          body: %{
            "choices" => [
              %{
                "message" => %{
                  "content" => "{\"maximum_value\":\"10\",\"minimum_value\":\"1\"}"
                }
              }
            ]
          }
        }
    end)

    assert %{
             success: true,
             parsed_msg: %{
               "minimum_value" => "1",
               "maximum_value" => "10"
             }
           } =
             CommonWebhook.webhook("parse_via_chat_gpt", fields)
  end

  test "send_wa_group_poll", attrs do
    fields = %{}

    assert %{success: false, error: "wa_group is invalid"} =
             CommonWebhook.webhook("send_wa_group_poll", fields)

    fields = %{
      "wa_group" => %{
        "wa_managed_phone_id" => 0,
        "id" => 0
      },
      "organization_id" => attrs.organization_id
    }

    assert %{success: false, error: "poll_uuid is invalid"} =
             CommonWebhook.webhook("send_wa_group_poll", fields)

    poll = Fixtures.wa_poll_fixture(%{label: "poll_a"})

    fields = %{
      "wa_group" => %{
        "wa_managed_phone_id" => 0,
        "id" => 0
      },
      "organization_id" => attrs.organization_id,
      "poll_uuid" => poll.uuid
    }

    assert %{
             success: false,
             error: "[\"Elixir.Glific.WAGroup.WAManagedPhone\", \"Resource not found\"]"
           } =
             CommonWebhook.webhook("send_wa_group_poll", fields)

    wa_phone = Fixtures.wa_managed_phone_fixture(attrs)
    wa_group = Fixtures.wa_group_fixture(Map.put(attrs, :wa_managed_phone_id, wa_phone.id))

    fields = %{
      "wa_group" => %{
        "wa_managed_phone_id" => wa_phone.id,
        "id" => wa_group.id
      },
      "organization_id" => attrs.organization_id,
      "poll_uuid" => poll.uuid
    }

    assert %{
             success: true,
             poll: _
           } =
             CommonWebhook.webhook("send_wa_group_poll", fields)
  end

  test "successfully creates a certificate" do
    Tesla.Mock.mock(fn
      %Tesla.Env{
        method: :post,
        url: "https://storage.googleapis.com/upload/storage/v1/b/mock-bucket-name/o",
        query: [uploadType: "multipart"]
      } ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body:
             Jason.encode!(%{
               "name" => "uploads/certificate/copied_presentation123/123.png",
               "mediaLink" =>
                 "https://storage.googleapis.com/mock-bucket-name/uploads/certificate/copied_presentation123/123.png",
               "selfLink" =>
                 "https://storage.googleapis.com/mock-bucket-name/uploads/certificate/copied_presentation123/123.png"
             })
         }}

      %{
        method: :get,
        url:
          "https://storage.googleapis.com/mock-bucket-name/uploads/certificate/copied_presentation123/123.png"
      } ->
        {:ok, %Tesla.Env{status: 200, body: "<<binary image data>>"}}

      %{
        method: :post,
        url:
          "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}/copy?supportsAllDrives=true"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(@mock_copied_slide)}}

      %{
        method: :post,
        url: "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}/permissions"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}

      %{
        method: :post,
        url: "https://slides.googleapis.com/v1/presentations/#{@mock_presentation_id}:batchUpdate"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}

      %{
        method: :get,
        url:
          "https://slides.googleapis.com/v1/presentations/#{@mock_presentation_id}/pages/g2/thumbnail"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(@mock_thumbnail)}}

      %{
        method: :get,
        url:
          "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}?supportsAllDrives=true"
      } ->
        {:ok, %Tesla.Env{status: 200, body: ""}}

      %{
        method: :get,
        url: "image_url"
      } ->
        {:ok, %Tesla.Env{status: 200, body: "<<binary image data>>"}}
    end)

    attrs = %{
      label: "test",
      type: :slides,
      url: "https://docs.google.com/presentation/d/#{@mock_presentation_id}/edit#slide=id.g2",
      organization_id: 1
    }

    with_mock(
      Goth.Token,
      [],
      fetch: fn _url ->
        {:ok, %{token: "mock_access_token", expires: System.system_time(:second) + 120}}
      end
    ) do
      {:ok, certificate} = CertificateTemplate.create_certificate_template(attrs)
      contact = Fixtures.contact_fixture()

      fields = %{
        "certificate_id" => certificate.id,
        "contact" => %{"id" => contact.id},
        "organization_id" => 1,
        "replace_texts" => %{"{1}" => "John Doe", "{2}" => "March 5, 2025"}
      }

      result = CommonWebhook.webhook("create_certificate", fields)
      assert result[:success] == true
      assert result[:certificate_url] == "https:storage.googleapis.com"
    end
  end

  test "Failed to create a certificate, thumbnail download failure" do
    Tesla.Mock.mock(fn
      %Tesla.Env{
        method: :post,
        url: "https://storage.googleapis.com/upload/storage/v1/b/mock-bucket-name/o",
        query: [uploadType: "multipart"]
      } ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body:
             Jason.encode!(%{
               "name" => "uploads/certificate/copied_presentation123/123.png",
               "mediaLink" =>
                 "https://storage.googleapis.com/mock-bucket-name/uploads/certificate/copied_presentation123/123.png",
               "selfLink" =>
                 "https://storage.googleapis.com/mock-bucket-name/uploads/certificate/copied_presentation123/123.png"
             })
         }}

      %{
        method: :get,
        url:
          "https://storage.googleapis.com/mock-bucket-name/uploads/certificate/copied_presentation123/123.png"
      } ->
        {:ok, %Tesla.Env{status: 200, body: "<<binary image data>>"}}

      %{
        method: :post,
        url:
          "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}/copy?supportsAllDrives=true"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(@mock_copied_slide)}}

      %{
        method: :post,
        url: "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}/permissions"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}

      %{
        method: :post,
        url: "https://slides.googleapis.com/v1/presentations/#{@mock_presentation_id}:batchUpdate"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}

      %{
        method: :get,
        url:
          "https://slides.googleapis.com/v1/presentations/#{@mock_presentation_id}/pages/g2/thumbnail"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(@mock_thumbnail)}}

      %{
        method: :get,
        url:
          "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}?supportsAllDrives=true"
      } ->
        {:ok, %Tesla.Env{status: 200, body: ""}}

      %{
        method: :get,
        url: "image_url"
      } ->
        {:ok, %Tesla.Env{status: 400, body: "<<binary image data>>"}}
    end)

    attrs = %{
      label: "test",
      type: :slides,
      url: "https://docs.google.com/presentation/d/#{@mock_presentation_id}/edit#slide=id.g2",
      organization_id: 1
    }

    with_mock(
      Goth.Token,
      [],
      fetch: fn _url ->
        {:ok, %{token: "mock_access_token", expires: System.system_time(:second) + 120}}
      end
    ) do
      {:ok, certificate} = CertificateTemplate.create_certificate_template(attrs)
      contact = Fixtures.contact_fixture()

      fields = %{
        "certificate_id" => certificate.id,
        "contact" => %{"id" => contact.id},
        "organization_id" => 1,
        "replace_texts" => %{"{1}" => "John Doe", "{2}" => "March 5, 2025"}
      }

      result = CommonWebhook.webhook("create_certificate", fields)
      assert result[:success] == false
      assert result[:reason] == "Failed to download thumbnail url"
    end
  end

  test "Failed to create a certificate, GCSWorker upload failure" do
    Tesla.Mock.mock(fn
      %Tesla.Env{
        method: :post,
        url: "https://storage.googleapis.com/upload/storage/v1/b/mock-bucket-name/o",
        query: [uploadType: "multipart"]
      } ->
        {:ok,
         %Tesla.Env{
           status: 400,
           body:
             Jason.encode!(%{
               "error" => %{"errors" => [%{"reason" => "something went wrong"}]}
             })
         }}

      %{
        method: :get,
        url:
          "https://storage.googleapis.com/mock-bucket-name/uploads/certificate/copied_presentation123/123.png"
      } ->
        {:ok, %Tesla.Env{status: 200, body: "<<binary image data>>"}}

      %{
        method: :post,
        url:
          "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}/copy?supportsAllDrives=true"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(@mock_copied_slide)}}

      %{
        method: :post,
        url: "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}/permissions"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}

      %{
        method: :post,
        url: "https://slides.googleapis.com/v1/presentations/#{@mock_presentation_id}:batchUpdate"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}

      %{
        method: :get,
        url:
          "https://slides.googleapis.com/v1/presentations/#{@mock_presentation_id}/pages/g2/thumbnail"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(@mock_thumbnail)}}

      %{
        method: :get,
        url:
          "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}?supportsAllDrives=true"
      } ->
        {:ok, %Tesla.Env{status: 200, body: ""}}

      %{
        method: :get,
        url: "image_url"
      } ->
        {:ok, %Tesla.Env{status: 200, body: "<<binary image data>>"}}
    end)

    attrs = %{
      label: "test",
      type: :slides,
      url: "https://docs.google.com/presentation/d/#{@mock_presentation_id}/edit#slide=id.g2",
      organization_id: 1
    }

    with_mock(
      Goth.Token,
      [],
      fetch: fn _url ->
        {:ok, %{token: "mock_access_token", expires: System.system_time(:second) + 120}}
      end
    ) do
      {:ok, certificate} = CertificateTemplate.create_certificate_template(attrs)
      contact = Fixtures.contact_fixture()

      fields = %{
        "certificate_id" => certificate.id,
        "contact" => %{"id" => contact.id},
        "organization_id" => 1,
        "replace_texts" => %{"{1}" => "John Doe", "{2}" => "March 5, 2025"}
      }

      result = CommonWebhook.webhook("create_certificate", fields)
      assert result[:success] == false
    end
  end

  test "Failure in creating a certificate" do
    Tesla.Mock.mock(fn
      %{
        method: :get,
        url:
          "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}?supportsAllDrives=true"
      } ->
        {:ok, %Tesla.Env{status: 200, body: ""}}

      %{
        method: :post,
        url:
          "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}/copy?supportsAllDrives=true"
      } ->
        {:ok, %Tesla.Env{status: 400, body: Jason.encode!(@mock_copied_slide)}}
    end)

    attrs = %{
      label: "test",
      type: :slides,
      url: "https://docs.google.com/presentation/d/#{@mock_presentation_id}/edit#slide=id.g2",
      organization_id: 1
    }

    with_mock(
      Goth.Token,
      [],
      fetch: fn _url ->
        {:ok, %{token: "mock_access_token", expires: System.system_time(:second) + 120}}
      end
    ) do
      {:ok, certificate} = CertificateTemplate.create_certificate_template(attrs)
      contact = Fixtures.contact_fixture()

      fields = %{
        "certificate_id" => certificate.id,
        "contact" => %{"id" => contact.id},
        "organization_id" => 1,
        "replace_texts" => %{"{1}" => "John Doe", "{2}" => "March 5, 2025"}
      }

      result = CommonWebhook.webhook("create_certificate", fields)
      assert result[:success] == false
      assert result[:certificate_url] == nil
    end
  end

  test "webhook/2 for creates_certificate should give error when certificate doesn't exist" do
    certificate_id = 111

    fields = %{
      "certificate_id" => certificate_id,
      "contact" => %{"id" => "123"},
      "organization_id" => 1,
      "replace_texts" => %{"{1}" => "John Doe", "{2}" => "March 5, 2025"}
    }

    result = CommonWebhook.webhook("create_certificate", fields)

    assert result[:success] == false
    assert result[:error] == "Certificate template not found for ID: #{certificate_id}"
  end

  test "webhook/2 for certificate should fail when validation fails" do
    # when certificate is invalid
    invalid_fields = %{}

    assert %{success: false, error: error} =
             CommonWebhook.webhook("create_certificate", invalid_fields)

    assert String.split(error, "is required") |> length() == 5

    # replace text
    invalid_fields = %{
      "certificate_id" => "1",
      "organization_id" => 1,
      "contact" => %{"id" => "123"},
      "replace_texts" => "John Doe"
    }

    assert %{error: "replace_texts is invalid", success: false} =
             CommonWebhook.webhook("create_certificate", invalid_fields)

    invalid_fields = %{
      "certificate_id" => "1",
      "organization_id" => 1,
      "replace_texts" => %{"{1}" => "John Doe", "{2}" => "March 5, 2025"}
    }

    assert %{error: "contact is required", success: false} =
             CommonWebhook.webhook("create_certificate", invalid_fields)

    invalid_fields = %{
      "certificate_id" => 0,
      "organization_id" => 1,
      "contact" => %{"id" => "123"},
      "replace_texts" => %{"{1}" => "John Doe", "{2}" => "March 5, 2025"}
    }

    assert %{error: "Certificate template not found" <> _} =
             CommonWebhook.webhook("create_certificate", invalid_fields)
  end
end
