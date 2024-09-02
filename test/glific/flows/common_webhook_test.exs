defmodule Glific.Flows.CommonWebhookTest do
  use Glific.DataCase, async: true
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Clients.CommonWebhook,
    Messages,
    Seeds.SeedsDev
  }

  import Mock

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
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
    assert result[:ward] == "N/A"
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
end
