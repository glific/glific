defmodule Glific.Flows.WebhookTest do
  use Glific.DataCase, async: true
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.Flows.{
    Action,
    FlowContext,
    Webhook,
    WebhookLog
  }

  alias Glific.{
    Clients.CommonWebhook,
    Fixtures,
    Messages,
    Seeds.SeedsDev
  }

  import Mock

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    :ok
  end

  describe "webhook" do
    @results %{
      "content" => "Your score: 31 is not divisible by 2, 3, 5 or 7",
      "score" => "31",
      "status" => "5"
    }
    @results_as_list [
      %{
        "content" => "Your score: 31 is not divisible by 2, 3, 5 or 7",
        "score" => "31",
        "status" => "5",
        "list_key" => [
          %{
            "list_nest_key" => "list_nest_value"
          }
        ]
      }
    ]

    @action_body %{
      contact: "@contact",
      results: "@results",
      custom_key: "custom_value"
    }

    test "successful geolocation response" do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(@results)
          }
      end)
    end

    test "execute a webhook for post method should return the response body with results",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(@results)
          }
      end)

      attrs = %{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: Fixtures.contact_fixture(attrs).id,
        organization_id: attrs.organization_id
      }

      {:ok, context} = FlowContext.create_flow_context(attrs)
      context = Repo.preload(context, [:contact, :flow])

      action = %Action{
        headers: %{"Accept" => "application/json"},
        method: "POST",
        url: "some url",
        body: Jason.encode!(@action_body)
      }

      assert Webhook.execute(action, context) == nil
      # we now need to wait for the Oban job and fire and then
      # check the results of the context
    end

    test "execute a webhook for post method should not break and update the webhook log in case of error",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 404,
            body: ""
          }
      end)

      attrs = %{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: Fixtures.contact_fixture(attrs).id,
        organization_id: attrs.organization_id
      }

      {:ok, context} = FlowContext.create_flow_context(attrs)
      context = Repo.preload(context, [:contact, :flow])
      contact_id = context.contact.id

      action = %Action{
        headers: %{"Accept" => "application/json", "custom_header" => "@contact.id"},
        method: "POST",
        url: "www.one.com/@contact.id",
        body: Jason.encode!(@action_body)
      }

      assert Webhook.execute(action, context) == nil
      webhook_log = List.first(WebhookLog.list_webhook_logs(%{filter: attrs}))

      assert webhook_log.request_headers["custom_header"] == Integer.to_string(contact_id)
      assert webhook_log.url == "www.one.com/#{contact_id}"
    end

    test "execute a webhook for post method should not break and update the webhook log in case of array/list response",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(@results_as_list)
          }
      end)

      attrs = %{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: Fixtures.contact_fixture(attrs).id,
        organization_id: attrs.organization_id
      }

      {:ok, context} = FlowContext.create_flow_context(attrs)
      context = Repo.preload(context, [:contact, :flow])

      action = %Action{
        headers: %{"Accept" => "application/json"},
        method: "POST",
        url: "some url",
        body: Jason.encode!(@action_body)
      }

      assert Webhook.execute(action, context) == nil
      Oban.drain_queue(queue: :webhook)

      webhook_log = List.first(WebhookLog.list_webhook_logs(%{filter: attrs}))

      response = webhook_log.response_json

      assert get_in(response, ["0", "list_key", "0", "list_nest_key"]) == "list_nest_value"
    end
  end

  describe "webhook logs" do
    @valid_attrs %{
      url: "some url",
      method: "GET",
      request_headers: %{
        "Accept" => "application/json",
        "X-Glific-Signature" => "random signature"
      },
      request_json: %{}
    }
    @update_attrs %{
      response_json: %{},
      status_code: 200
    }

    test "create_webhook_log/1 with valid data creates a webhook_log",
         %{organization_id: _organization_id} = attrs do
      flow = Fixtures.flow_fixture(attrs)
      contact = Fixtures.contact_fixture(attrs)

      valid_attrs =
        @valid_attrs
        |> Map.put(:contact_id, contact.id)
        |> Map.put(:flow_id, flow.id)
        |> Map.put(:organization_id, flow.organization_id)

      assert {:ok, %WebhookLog{}} = WebhookLog.create_webhook_log(valid_attrs)
    end

    test "update_webhook_log/2 with valid data updates the webhook_log", attrs do
      flow = Fixtures.flow_fixture(attrs)
      contact = Fixtures.contact_fixture(attrs)

      valid_attrs =
        @valid_attrs
        |> Map.put(:contact_id, contact.id)
        |> Map.put(:flow_id, flow.id)
        |> Map.put(:organization_id, flow.organization_id)

      {:ok, webhook_log} = WebhookLog.create_webhook_log(valid_attrs)

      assert {:ok, %WebhookLog{} = webhook_log} =
               WebhookLog.update_webhook_log(webhook_log, @update_attrs)

      assert webhook_log.status_code == 200
    end

    test "list_webhook_logs/2", attrs do
      webhook_log = Fixtures.webhook_log_fixture(attrs)

      assert [Map.merge(webhook_log, %{status: "Success"})] ==
               WebhookLog.list_webhook_logs(%{filter: attrs})
    end

    test "list_webhook_logs/2 returns filtered logs", attrs do
      webhook_log_1 = Fixtures.webhook_log_fixture(attrs)
      :timer.sleep(1000)

      valid_attrs_2 = Map.merge(attrs, %{url: "test_url_2", status_code: 500})
      webhook_log_2 = Fixtures.webhook_log_fixture(valid_attrs_2)

      assert [Map.merge(webhook_log_2, %{status: "Error"})] ==
               WebhookLog.list_webhook_logs(%{filter: %{status_code: 500}})

      assert [Map.merge(webhook_log_1, %{status: "Success"})] ==
               WebhookLog.list_webhook_logs(%{filter: %{status_code: 200, status: "Success"}})

      assert [Map.merge(webhook_log_1, %{status: "Success"})] ==
               WebhookLog.list_webhook_logs(%{filter: %{url: @valid_attrs.url}})

      #  order by inserted at
      assert [
               Map.merge(webhook_log_2, %{status: "Error"}),
               Map.merge(webhook_log_1, %{status: "Success"})
             ] ==
               WebhookLog.list_webhook_logs(%{opts: %{order: :desc}, filter: attrs})

      #  filter by contact_phone

      webhook_log = webhook_log_1 |> Repo.preload([:contact])
      phone = webhook_log.contact.phone

      assert [
               Map.merge(webhook_log_1, %{status: "Success"})
             ] ==
               WebhookLog.list_webhook_logs(%{
                 filter: %{contact_phone: phone}
               })
    end

    test "count_webhook_logs/0 returns count of all webhook logs", attrs do
      logs_count = WebhookLog.count_webhook_logs(%{filter: attrs})

      Fixtures.webhook_log_fixture(attrs)

      assert WebhookLog.count_webhook_logs(%{filter: attrs}) == logs_count + 1
    end
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

  @tag :respo
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

  @tag :respo
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

  @tag :respo
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

  @tag :respo
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

  @tag :respo
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

  end
end
