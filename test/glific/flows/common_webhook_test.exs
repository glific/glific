defmodule Glific.Flows.CommonWebhookTest do
  use Glific.DataCase
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Certificates.CertificateTemplate,
    Clients.CommonWebhook,
    Fixtures,
    Flows.Webhook.SystemError,
    Messages,
    Partners,
    Partners.Provider,
    Repo,
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

  describe "speech_to_text webhook" do
    setup do
      contact = Fixtures.contact_fixture()

      {:ok, _} =
        Partners.create_credential(%{
          organization_id: 1,
          shortcode: "kaapi",
          keys: %{},
          secrets: %{"api_key" => "test_api_key"},
          is_active: true
        })

      Partners.get_organization!(1) |> Partners.fill_cache()
      %{fields: stt_fields(contact.id)}
    end

    test "returns success when Kaapi acknowledges the STT request", %{fields: fields} do
      Tesla.Mock.mock(fn
        %{method: :get} -> %Tesla.Env{status: 200, body: "fake_audio_bytes"}
        %{method: :post} -> %Tesla.Env{status: 200, body: %{request_id: "req_123"}}
      end)

      result = CommonWebhook.webhook("speech_to_text", fields, [])
      assert result.success == true
    end

    test "sends correct payload structure to Kaapi for STT", %{fields: fields} do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{status: 200, body: "fake_audio_bytes"}

        %{method: :post, body: body} ->
          decoded = Jason.decode!(body)

          assert get_in(decoded, ["query", "input", "type"]) == "audio"
          assert get_in(decoded, ["query", "input", "content", "format"]) == "base64"
          assert get_in(decoded, ["config", "blob", "completion", "type"]) == "stt"
          assert get_in(decoded, ["config", "blob", "completion", "provider"]) == "google"

          assert get_in(decoded, ["config", "blob", "completion", "params", "model"]) ==
                   "gemini-2.5-pro"

          assert get_in(decoded, ["config", "blob", "completion", "params", "input_language"]) ==
                   "auto"

          params = get_in(decoded, ["config", "blob", "completion", "params"])
          refute Map.has_key?(params, "output_language")

          metadata = decoded["request_metadata"]
          assert metadata["organization_id"] == 1
          assert metadata["flow_id"] == 1
          assert metadata["webhook_log_id"] == 1
          assert metadata["result_name"] == "response"
          assert decoded["callback_url"] =~ "/webhook/flow_resume"

          %Tesla.Env{status: 200, body: %{"job_id" => "stt-123"}}
      end)

      result = CommonWebhook.webhook("speech_to_text", fields, [])
      assert result.success == true
    end

    test "passes output_language to Kaapi when specified in fields", %{fields: fields} do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{status: 200, body: "fake_audio_bytes"}

        %{method: :post, body: body} ->
          decoded = Jason.decode!(body)

          assert get_in(decoded, ["config", "blob", "completion", "params", "output_language"]) ==
                   "english"

          %Tesla.Env{status: 200, body: %{"job_id" => "stt-456"}}
      end)

      result =
        CommonWebhook.webhook("speech_to_text", Map.put(fields, "output_language", "english"), [])

      assert result.success == true
    end
  end

  describe "text_to_speech webhook" do
    setup do
      contact = Fixtures.contact_fixture()

      {:ok, _} =
        Partners.create_credential(%{
          organization_id: 1,
          shortcode: "kaapi",
          keys: %{},
          secrets: %{"api_key" => "test_api_key"},
          is_active: true
        })

      Partners.get_organization!(1) |> Partners.fill_cache()
      %{fields: tts_fields(contact.id)}
    end

    test "returns success when Kaapi acknowledges the TTS request", %{fields: fields} do
      Tesla.Mock.mock(fn
        %{method: :post} -> %Tesla.Env{status: 200, body: %{request_id: "req_456"}}
      end)

      result = CommonWebhook.webhook("text_to_speech", fields, [])
      assert result.success == true
    end

    test "sends correct payload structure to Kaapi for TTS", %{fields: fields} do
      Tesla.Mock.mock(fn
        %{method: :post, body: body} ->
          decoded = Jason.decode!(body)

          assert get_in(decoded, ["query", "input"]) == "Hello world"
          assert get_in(decoded, ["config", "blob", "completion", "type"]) == "tts"
          assert get_in(decoded, ["config", "blob", "completion", "provider"]) == "google"

          assert get_in(decoded, ["config", "blob", "completion", "params", "model"]) ==
                   "gemini-2.5-pro-preview-tts"

          assert get_in(decoded, ["config", "blob", "completion", "params", "voice"]) == "Kore"

          assert get_in(decoded, ["config", "blob", "completion", "params", "language"]) ==
                   "hindi"

          metadata = decoded["request_metadata"]
          assert metadata["organization_id"] == 1
          assert metadata["flow_id"] == 1
          assert metadata["webhook_log_id"] == 1
          assert metadata["result_name"] == "response"
          assert decoded["callback_url"] =~ "/webhook/flow_resume"

          %Tesla.Env{status: 200, body: %{"job_id" => "tts-456"}}
      end)

      result = CommonWebhook.webhook("text_to_speech", fields, [])
      assert result.success == true
    end
  end

  describe "speech_to_text_with_bhasini failure reporting" do
    setup do
      contact = Fixtures.contact_fixture()
      %{contact: contact, fields: bhasini_stt_fields(contact.id)}
    end

    test "emits SystemError with http_status tag on Gemini 4xx response", %{fields: fields} do
      Tesla.Mock.mock(fn
        %{method: :get} -> %Tesla.Env{status: 200, body: "fake_audio_bytes"}
        %{method: :post} -> %Tesla.Env{status: 401, body: %{}}
      end)

      {exception, tags} =
        capture_appsignal(fn ->
          result = CommonWebhook.webhook("speech_to_text_with_bhasini", fields)
          assert result.success == false
        end)

      assert %SystemError{} = exception

      assert Exception.message(exception) ==
               "Webhook system_error from speech_to_text_with_bhasini"

      assert tags.webhook_name == "speech_to_text_with_bhasini"
      assert tags.organization_id == 1
      assert tags.http_status == 401
      assert is_nil(tags.reason)
    end

    test "emits SystemError with reason tag when audio download fails", %{fields: fields} do
      Tesla.Mock.mock(fn
        %{method: :get} -> %Tesla.Env{status: 404, body: ""}
      end)

      {exception, tags} =
        capture_appsignal(fn ->
          result = CommonWebhook.webhook("speech_to_text_with_bhasini", fields)
          assert result.success == false
          assert result.asr_response_text == "File download failed"
        end)

      assert %SystemError{} = exception
      assert tags.reason == "File download failed"
      assert is_nil(tags.http_status)
    end

    test "does not call AppSignal on successful Gemini response", %{fields: fields} do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{status: 200, body: "fake_audio_bytes"}

        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{
              candidates: [%{content: %{parts: [%{text: ~s("transcribed text")}]}}],
              usageMetadata: %{totalTokenCount: 10}
            }
          }
      end)

      test_pid = self()

      with_mocks([
        {Appsignal, [:passthrough],
         [
           send_error: fn _ex, _stack, _fn ->
             send(test_pid, :appsignal_called)
             :ok
           end
         ]}
      ]) do
        result = CommonWebhook.webhook("speech_to_text_with_bhasini", fields)
        assert result.success == true
      end

      refute_received :appsignal_called
    end

    test "rescue path reports SystemError and reraises on unexpected exception", %{
      fields: fields
    } do
      # Gemini returns 200 with a `text` field that isn't valid JSON.
      # ApiClient's success branch does Jason.decode!(text), which raises.
      # The try/rescue in CommonWebhook must catch, report, and reraise.
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{status: 200, body: "fake_audio_bytes"}

        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{
              candidates: [%{content: %{parts: [%{text: "not valid json {{{"}]}}],
              usageMetadata: %{totalTokenCount: 1}
            }
          }
      end)

      {exception, _tags} =
        capture_appsignal(fn ->
          assert_raise Jason.DecodeError, fn ->
            CommonWebhook.webhook("speech_to_text_with_bhasini", fields)
          end
        end)

      assert %SystemError{} = exception
    end
  end

  describe "text_to_speech_with_bhasini failure reporting" do
    setup do
      contact = Fixtures.contact_fixture()
      %{contact: contact, fields: bhasini_tts_fields(contact.id)}
    end

    test "emits SystemError with http_status tag on Gemini 4xx response", %{fields: fields} do
      Tesla.Mock.mock(fn
        %{method: :post} -> %Tesla.Env{status: 401, body: %{}}
      end)

      {exception, tags} =
        capture_appsignal(fn ->
          result = CommonWebhook.webhook("text_to_speech_with_bhasini", fields)
          assert result.success == false
        end)

      assert %SystemError{} = exception

      assert Exception.message(exception) ==
               "Webhook system_error from text_to_speech_with_bhasini"

      assert tags.webhook_name == "text_to_speech_with_bhasini"
      assert tags.organization_id == 1
      assert tags.http_status == 401
    end

    test "emits SystemError on OpenAI TTS failure (speech_engine = open_ai)", %{fields: fields} do
      fields = Map.put(fields, "speech_engine", "open_ai")

      Tesla.Mock.mock(fn %{method: :post} ->
        %Tesla.Env{status: 401, body: %{}}
      end)

      {exception, tags} =
        capture_appsignal(fn ->
          CommonWebhook.webhook("text_to_speech_with_bhasini", fields)
        end)

      assert %SystemError{} = exception
      assert tags.webhook_name == "text_to_speech_with_bhasini"
      assert tags.organization_id == 1
    end
  end

  # Runs `fun` with Appsignal.send_error and Appsignal.Span.set_sample_data
  # mocked. Returns {exception, tags} captured from the production code's
  # reporting call.
  defp capture_appsignal(fun) do
    test_pid = self()

    with_mocks([
      {Appsignal, [:passthrough],
       [
         send_error: fn ex, _stack, configurator ->
           send(test_pid, {:appsignal_exception, ex})
           configurator.(:fake_span)
           :ok
         end
       ]},
      {Appsignal.Span, [:passthrough],
       [
         set_sample_data: fn _span, key, value ->
           send(test_pid, {:appsignal_tag, key, value})
           :fake_span
         end
       ]}
    ]) do
      fun.()
    end

    exception =
      receive do
        {:appsignal_exception, ex} -> ex
      after
        100 -> flunk("Appsignal.send_error was not called")
      end

    tags =
      receive do
        {:appsignal_tag, "tags", t} -> t
      after
        100 -> %{}
      end

    {exception, tags}
  end

  defp bhasini_stt_fields(contact_id) do
    %{
      "speech" => "https://filemanager.gupshup.io/wa/audio.ogg",
      "organization_id" => 1,
      "contact" => %{"id" => to_string(contact_id)}
    }
  end

  defp bhasini_tts_fields(contact_id) do
    %{
      "text" => "Hello world",
      "organization_id" => "1",
      "contact" => %{"id" => to_string(contact_id)},
      "speech_engine" => "bhashini"
    }
  end

  defp stt_fields(contact_id) do
    %{
      "speech" => "https://filemanager.gupshup.io/wa/audio.ogg",
      "organization_id" => "1",
      "flow_id" => "1",
      "contact_id" => "#{contact_id}",
      "webhook_log_id" => 1,
      "result_name" => "response"
    }
  end

  describe "unified-llm-call lookup_kaapi_config" do
    setup do
      {:ok, _credential} =
        Partners.create_credential(%{
          organization_id: 1,
          shortcode: "kaapi",
          keys: %{},
          secrets: %{"api_key" => "sk_test_key"},
          is_active: true
        })

      Partners.get_organization!(1) |> Partners.fill_cache()
      :ok
    end

    test "returns error when assistant_id is nil" do
      fields = %{
        "question" => "test",
        "organization_id" => "1",
        "flow_id" => "1",
        "contact_id" => "2",
        "webhook_log_id" => 1,
        "result_name" => "response"
      }

      headers = [{"X-API-KEY", "sk_test_key"}]
      result = CommonWebhook.webhook("unified-llm-call", fields, headers)

      assert result[:success] == false
      assert result[:reason] == "assistant_id is required"
    end

    test "returns error when assistant not found" do
      fields = %{
        "assistant_id" => "nonexistent_id",
        "question" => "test",
        "organization_id" => "1",
        "flow_id" => "1",
        "contact_id" => "2",
        "webhook_log_id" => 1,
        "result_name" => "response"
      }

      headers = [{"X-API-KEY", "sk_test_key"}]
      result = CommonWebhook.webhook("unified-llm-call", fields, headers)

      assert result[:success] == false
      assert result[:reason] =~ "Assistant not found"
    end

    test "returns error when kaapi_version_number is nil" do
      alias Glific.Assistants.{Assistant, AssistantConfigVersion}

      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Version Nil Test",
          organization_id: 1,
          kaapi_uuid: "kaapi_uuid_test"
        })
        |> Repo.insert()

      {:ok, config} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: 1,
          provider: "openai",
          model: "gpt-4o",
          prompt: "test",
          settings: %{},
          status: :ready,
          kaapi_version_number: nil
        })
        |> Repo.insert()

      {:ok, assistant} =
        assistant
        |> Assistant.set_active_config_version_changeset(%{
          active_config_version_id: config.id
        })
        |> Repo.update()

      fields = %{
        "assistant_id" => assistant.assistant_display_id,
        "question" => "test",
        "organization_id" => "1",
        "flow_id" => "1",
        "contact_id" => "2",
        "webhook_log_id" => 1,
        "result_name" => "response"
      }

      headers = [{"X-API-KEY", "sk_test_key"}]
      result = CommonWebhook.webhook("unified-llm-call", fields, headers)

      assert result[:success] == false
      assert result[:reason] =~ "Kaapi version number not found"
    end

    test "returns error when kaapi_uuid is nil" do
      alias Glific.Assistants.{Assistant, AssistantConfigVersion}

      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "No UUID Test",
          organization_id: 1
        })
        |> Repo.insert()

      {:ok, config} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: 1,
          provider: "openai",
          model: "gpt-4o",
          prompt: "test",
          settings: %{},
          status: :ready
        })
        |> Repo.insert()

      {:ok, assistant} =
        assistant
        |> Assistant.set_active_config_version_changeset(%{
          active_config_version_id: config.id
        })
        |> Repo.update()

      fields = %{
        "assistant_id" => assistant.assistant_display_id,
        "question" => "test",
        "organization_id" => "1",
        "flow_id" => "1",
        "contact_id" => "2",
        "webhook_log_id" => 1,
        "result_name" => "response"
      }

      headers = [{"X-API-KEY", "sk_test_key"}]
      result = CommonWebhook.webhook("unified-llm-call", fields, headers)

      assert result[:success] == false
      assert result[:reason] =~ "Assistant is still being set up"
    end
  end

  defp tts_fields(contact_id) do
    %{
      "text" => "Hello world",
      "organization_id" => "1",
      "flow_id" => "1",
      "contact_id" => "#{contact_id}",
      "webhook_log_id" => 1,
      "result_name" => "response"
    }
  end

  defp create_assistant_with_config(organization_id, opts) do
    assistant_display_id = Keyword.get(opts, :assistant_display_id, "asst_test_123")
    kaapi_uuid = Keyword.get(opts, :kaapi_uuid, "kaapi-uuid-test-456")

    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{
        name: "Test Assistant",
        organization_id: organization_id,
        kaapi_uuid: kaapi_uuid,
        assistant_display_id: assistant_display_id
      })
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        version_number: 1,
        kaapi_version_number: 1,
        prompt: "You are a helpful assistant.",
        provider: "openai",
        model: "gpt-4o",
        settings: %{},
        status: :ready,
        organization_id: organization_id
      })
      |> Repo.insert()

    assistant
    |> Assistant.set_active_config_version_changeset(%{
      active_config_version_id: config_version.id
    })
    |> Repo.update()

    {assistant, config_version}
  end

  defp unified_llm_headers do
    [{"X-API-KEY", "test-api-key"}]
  end

  describe "unified-voice-llm-call webhook" do
    test "does STT then calls unified LLM with voice callback path" do
      organization_id = 1
      assistant_display_id = "asst_voice_test"
      create_assistant_with_config(organization_id, assistant_display_id: assistant_display_id)

      contact = Fixtures.contact_fixture()

      fields =
        %{
          "organization_id" => organization_id,
          "flow_id" => 1,
          "contact_id" => contact.id,
          "contact" => %{"id" => contact.id},
          "assistant_id" => assistant_display_id,
          "speech" => "https://example.com/audio.ogg",
          "source_language" => "english",
          "target_language" => "hindi",
          "webhook_log_id" => 1,
          "result_name" => "result"
        }

      test_pid = self()

      Tesla.Mock.mock(fn
        %Tesla.Env{method: :get, url: "https://example.com/audio.ogg"} ->
          send(test_pid, :audio_downloaded)
          %Tesla.Env{status: 200, body: "fake-audio-bytes"}

        %Tesla.Env{method: :post, url: url, body: body} ->
          cond do
            String.contains?(url, "generativelanguage.googleapis.com") ->
              send(test_pid, {:stt_called, body})

              %Tesla.Env{
                status: 200,
                body: %{
                  candidates: [
                    %{content: %{parts: [%{text: Jason.encode!("Hello world")}]}}
                  ],
                  usageMetadata: %{
                    promptTokenCount: 10,
                    candidatesTokenCount: 5,
                    totalTokenCount: 15
                  }
                }
              }

            String.contains?(url, "/api/v1/llm/call") ->
              send(test_pid, {:llm_called, body})

              %Tesla.Env{
                status: 200,
                body: %{data: %{message: "LLM call started", success: true}}
              }

            true ->
              %Tesla.Env{status: 200, body: %{}}
          end
      end)

      result =
        CommonWebhook.webhook("unified-voice-llm-call", fields, unified_llm_headers())

      assert result.success == true

      # Verify STT pipeline: audio was downloaded and sent to Gemini for transcription
      assert_received :audio_downloaded
      assert_received {:stt_called, stt_body}
      stt_body = if is_binary(stt_body), do: Jason.decode!(stt_body), else: stt_body

      inline_data =
        get_in(stt_body, ["contents", Access.at(0), "parts", Access.at(0), "inline_data"])

      assert inline_data["mime_type"] == "audio/mp3"
      assert inline_data["data"] == Base.encode64("fake-audio-bytes")

      # Verify the unified LLM call receives the correct payload
      assert_received {:llm_called, llm_body}
      llm_body = if is_binary(llm_body), do: Jason.decode!(llm_body), else: llm_body

      # Query contains the transcribed text from STT
      assert get_in(llm_body, ["query", "input"]) == "Hello world"
      assert get_in(llm_body, ["query", "conversation", "auto_create"]) == true

      # Config contains the assistant's Kaapi UUID and version
      assert is_binary(get_in(llm_body, ["config", "id"]))
      assert is_integer(get_in(llm_body, ["config", "version"]))

      # Callback URL points to voice_flow_resume (not regular flow_resume)
      assert String.contains?(llm_body["callback_url"], "/kaapi/voice_flow_resume")

      # Request metadata includes flow context and voice post-processing fields
      metadata = llm_body["request_metadata"]
      assert metadata["organization_id"] == organization_id
      assert metadata["flow_id"] == 1
      assert metadata["contact_id"] == contact.id
      assert metadata["webhook_log_id"] == 1
      assert metadata["result_name"] == "result"
      assert metadata["voice_post_process"]["source_language"] == "english"
      assert metadata["voice_post_process"]["target_language"] == "hindi"
    end

    test "returns failure when STT fails" do
      organization_id = 1

      contact = Fixtures.contact_fixture()

      fields = %{
        "organization_id" => organization_id,
        "flow_id" => 1,
        "contact_id" => contact.id,
        "contact" => %{"id" => contact.id},
        "assistant_id" => "asst_voice_stt_fail",
        "speech" => "https://example.com/audio.ogg",
        "source_language" => "english",
        "target_language" => "hindi",
        "webhook_log_id" => 1,
        "result_name" => "result"
      }

      Tesla.Mock.mock(fn
        %Tesla.Env{method: :get} ->
          %Tesla.Env{status: 500, body: "download failed"}

        %Tesla.Env{method: :post} ->
          %Tesla.Env{status: 500, body: Jason.encode!(%{"error" => "STT failed"})}
      end)

      result =
        CommonWebhook.webhook("unified-voice-llm-call", fields, unified_llm_headers())

      assert result == %{success: false, reason: "File download failed"}
    end

    test "uses /kaapi/voice_flow_resume callback path and includes voice metadata" do
      organization_id = 1
      assistant_display_id = "asst_voice_meta"
      create_assistant_with_config(organization_id, assistant_display_id: assistant_display_id)

      contact = Fixtures.contact_fixture()

      fields = %{
        "organization_id" => organization_id,
        "flow_id" => 1,
        "contact_id" => contact.id,
        "contact" => %{"id" => contact.id},
        "assistant_id" => assistant_display_id,
        "speech" => "https://example.com/audio.ogg",
        "source_language" => "english",
        "target_language" => "hindi",
        "speech_engine" => "bhashini",
        "webhook_log_id" => 1,
        "result_name" => "result"
      }

      test_pid = self()

      Tesla.Mock.mock(fn
        %Tesla.Env{method: :get, url: "https://example.com/audio.ogg"} ->
          %Tesla.Env{status: 200, body: "fake-audio-bytes"}

        %Tesla.Env{method: :post, url: url, body: body} ->
          cond do
            String.contains?(url, "generativelanguage.googleapis.com") ->
              %Tesla.Env{
                status: 200,
                body: %{
                  candidates: [
                    %{content: %{parts: [%{text: Jason.encode!("Transcribed audio")}]}}
                  ],
                  usageMetadata: %{
                    promptTokenCount: 10,
                    candidatesTokenCount: 5,
                    totalTokenCount: 15
                  }
                }
              }

            String.contains?(url, "/api/v1/llm/call") ->
              decoded = if is_binary(body), do: Jason.decode!(body, keys: :atoms), else: body
              send(test_pid, {:llm_call, decoded})

              %Tesla.Env{
                status: 200,
                body: %{data: %{message: "ok", success: true}}
              }

            true ->
              %Tesla.Env{status: 200, body: %{}}
          end
      end)

      result =
        CommonWebhook.webhook("unified-voice-llm-call", fields, unified_llm_headers())

      assert result.success == true

      assert_receive {:llm_call, payload}
      assert payload.callback_url =~ "/kaapi/voice_flow_resume"

      assert payload.request_metadata.voice_post_process == %{
               source_language: "english",
               target_language: "hindi",
               speech_engine: "bhashini"
             }

      assert payload.query.input == "Transcribed audio"
    end
  end
end
