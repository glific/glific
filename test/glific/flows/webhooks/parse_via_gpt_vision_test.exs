defmodule Glific.Flows.Webhooks.ParseViaGptVisionTest do
  use Glific.DataCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  import Glific.WebhookTestHelpers

  alias Glific.{
    Fixtures,
    Flows.Action,
    Flows.Flow,
    Flows.FlowContext,
    Flows.Webhook,
    Flows.Webhooks.Dispatcher,
    Flows.WebhookLog,
    Messages,
    Repo,
    Seeds.SeedsDev
  }

  import Mock

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    :ok
  end

  # Build a FlowContext linked to the real call_and_wait flow so that
  # FlowContext.wakeup_one/2 can load the flow and advance it after the
  # webhook job completes.
  defp build_context(attrs) do
    contact = Fixtures.contact_fixture(attrs)
    flow = Flow.get_loaded_flow(attrs.organization_id, "published", %{keyword: "call_and_wait"})
    [node | _] = flow.nodes

    flow_attrs = %{
      flow_id: flow.id,
      contact_id: contact.id,
      organization_id: attrs.organization_id
    }

    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: contact.id,
        flow_id: flow.id,
        flow_uuid: flow.uuid,
        organization_id: attrs.organization_id,
        node_uuid: node.uuid,
        is_await_result: true
      })

    {Repo.preload(context, [:contact, :flow]), flow_attrs}
  end

  describe "parse_via_gpt_vision" do
    test "happy path returns success and resumes flow on success branch", attrs do
      with_mock(
        Messages,
        [:passthrough],
        validate_media: fn _, _ -> %{is_valid: true, message: "success"} end
      ) do
        Tesla.Mock.mock(fn
          # The webhook downloads the image and inlines it as a base64 data URL before
          # calling OpenAI, so the media GET must be mocked too.
          %{method: :get, url: "https://example.com/image.jpg"} ->
            %Tesla.Env{
              status: 200,
              body: "fake-image-bytes",
              headers: [{"content-type", "image/jpeg"}]
            }

          %{url: "https://api.openai.com/v1/chat/completions"} ->
            %Tesla.Env{
              status: 200,
              body: %{
                "choices" => [
                  %{
                    "message" => %{
                      "content" =>
                        "{\"summary\":\"A car on a road\",\"detected_objects\":[\"car\",\"road\"]}"
                    }
                  }
                ]
              }
            }
        end)

        {context, flow_attrs} = build_context(attrs)

        action = %Action{
          method: "FUNCTION",
          url: "parse_via_gpt_vision",
          headers: %{"Content-Type" => "application/json"},
          body:
            Jason.encode!(%{
              prompt: "Describe this image",
              url: "https://example.com/image.jpg",
              model: "gpt-4o"
            }),
          result_name: "filesearch"
        }

        assert Webhook.execute(action, context) == nil
        Oban.drain_queue(queue: :gpt_webhook_queue)

        # WebhookLog assertions — verify the webhook itself succeeded
        log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
        assert log.status == "Success"
        assert log.response_json["success"] == true

        # Flow execution assertion — verify the flow resumed on the success branch.
        # The call_and_wait success node sends "@results.filesearch.message"; since
        # the gpt_vision result has no "message" key, the template expression is
        # rendered as-is, proving the flow engine advanced past the webhook node.
        message = await_flow_message(context.contact_id, "@results.filesearch.message")
        assert message.body == "@results.filesearch.message"
      end
    end

    test "failure - API returns 500 error, log records it and flow takes failure branch", attrs do
      with_mock(
        Messages,
        [:passthrough],
        validate_media: fn _, _ -> %{is_valid: true, message: "success"} end
      ) do
        Tesla.Mock.mock(fn
          # The webhook downloads the image and inlines it as a base64 data URL before
          # calling OpenAI, so the media GET must be mocked too.
          %{method: :get, url: "https://example.com/image.jpg"} ->
            %Tesla.Env{
              status: 200,
              body: "fake-image-bytes",
              headers: [{"content-type", "image/jpeg"}]
            }

          %{url: "https://api.openai.com/v1/chat/completions"} ->
            %Tesla.Env{
              status: 500,
              body: Jason.encode!(%{"error" => %{"message" => "Internal Server Error"}})
            }
        end)

        {context, flow_attrs} = build_context(attrs)

        action = %Action{
          method: "FUNCTION",
          url: "parse_via_gpt_vision",
          headers: %{"Content-Type" => "application/json"},
          body:
            Jason.encode!(%{
              prompt: "Describe this image",
              url: "https://example.com/image.jpg",
              model: "gpt-4o"
            }),
          result_name: "filesearch"
        }

        assert Webhook.execute(action, context) == nil
        Oban.drain_queue(queue: :gpt_webhook_queue)

        # WebhookLog assertions — verify the webhook recorded the failure
        log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
        assert log != nil
        assert log.status_code >= 400 or log.error != nil

        # Flow execution assertion — webhook failure routes to the Failure branch
        message = await_flow_message(context.contact_id, "failure")
        assert message.body == "failure"
      end
    end
  end

  # Dispatch-level tests: exercise call/2 (media validation, base64 inlining, response_format
  # handling) directly via the Dispatcher, independent of the Oban/flow-resume path above.
  describe "parse_via_gpt_vision dispatch" do
    test "without response_format params, trying to get valid json" do
      with_mock(Messages, validate_media: fn _, _ -> %{is_valid: true, message: "success"} end) do
        Tesla.Mock.mock(fn
          %{method: :get} ->
            %Tesla.Env{
              status: 200,
              body: "image-bytes",
              headers: [{"content-type", "image/jpeg"}]
            }

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
          "prompt" => "value of steps is 4 and value of answer is 10, give in valid json",
          "url" => "https://fastly.picsum.photos/id/145/200/300.jpg?hmac=abc",
          "model" => "gpt-4o"
        }

        assert %{success: true, response: "```json\n{\n  \"steps\": 4,\n  \"answer\": 10\n}\n```"} =
                 Dispatcher.dispatch("parse_via_gpt_vision", fields)
      end
    end

    test "with response_format type json_object, trying to get valid json" do
      with_mock(Messages, validate_media: fn _, _ -> %{is_valid: true, message: "success"} end) do
        Tesla.Mock.mock(fn
          %{method: :get} ->
            %Tesla.Env{
              status: 200,
              body: "image-bytes",
              headers: [{"content-type", "image/jpeg"}]
            }

          %{url: "https://api.openai.com/v1/chat/completions"} ->
            %Tesla.Env{
              status: 200,
              body: %{
                "choices" => [
                  %{"message" => %{"content" => "{\n  \"steps\": 4,\n  \"answer\": 10\n}"}}
                ]
              }
            }
        end)

        fields = %{
          "prompt" => "value of steps is 4 and value of answer is 10, give in valid json",
          "url" => "https://fastly.picsum.photos/id/145/200/300.jpg?hmac=abc",
          "model" => "gpt-4o",
          "response_format" => %{"type" => "json_object"}
        }

        assert %{success: true, response: %{"steps" => 4, "answer" => 10}} =
                 Dispatcher.dispatch("parse_via_gpt_vision", fields)
      end
    end

    test "with invalid response_format param" do
      with_mock(Messages, validate_media: fn _, _ -> %{is_valid: true, message: "success"} end) do
        Tesla.Mock.mock(fn
          %{method: :get} ->
            %Tesla.Env{
              status: 200,
              body: "image-bytes",
              headers: [{"content-type", "image/jpeg"}]
            }

          %{url: "https://api.openai.com/v1/chat/completions"} ->
            %Tesla.Env{
              status: 200,
              body: %{
                "choices" => [
                  %{"message" => %{"content" => "{\n  \"steps\": 4,\n  \"answer\": 10\n}"}}
                ]
              }
            }
        end)

        fields = %{
          "prompt" => "value of steps is 4 and value of answer is 10, give in valid json",
          "url" => "https://fastly.picsum.photos/id/145/200/300.jpg?hmac=abc",
          "model" => "gpt-4o",
          "response_format" => %{"type" => "json_objectz"}
        }

        assert "response_format type should be json_schema or json_object" =
                 Dispatcher.dispatch("parse_via_gpt_vision", fields)
      end
    end

    test "with response_format json_schema, trying to get valid json" do
      with_mock(Messages, validate_media: fn _, _ -> %{is_valid: true, message: "success"} end) do
        Tesla.Mock.mock(fn
          %{method: :get} ->
            %Tesla.Env{
              status: 200,
              body: "image-bytes",
              headers: [{"content-type", "image/jpeg"}]
            }

          %{url: "https://api.openai.com/v1/chat/completions"} ->
            %Tesla.Env{
              status: 200,
              body: %{
                "choices" => [
                  %{
                    "message" => %{"content" => "{\n  \"steps\": \"4\",\n  \"answer\": \"10\"\n}"}
                  }
                ]
              }
            }
        end)

        fields = %{
          "prompt" => "value of steps is 4 and value of answer is 10, give in valid json",
          "url" => "https://fastly.picsum.photos/id/145/200/300.jpg?hmac=abc",
          "model" => "gpt-4o",
          "response_format" => %{
            "type" => "json_schema",
            "json_schema" => %{
              "name" => "schemaing",
              "strict" => true,
              "schema" => %{
                "type" => "object",
                "properties" => %{
                  "steps" => %{"type" => "string"},
                  "answer" => %{"type" => "string"}
                },
                "required" => ["steps", "answer"],
                "additionalProperties" => false
              }
            }
          }
        }

        assert %{success: true, response: %{"steps" => "4", "answer" => "10"}} =
                 Dispatcher.dispatch("parse_via_gpt_vision", fields)
      end
    end

    test "with response_format json_schema but a non-nil refusal returns the refusal" do
      with_mock(Messages, validate_media: fn _, _ -> %{is_valid: true, message: "success"} end) do
        Tesla.Mock.mock(fn
          %{method: :get} ->
            %Tesla.Env{
              status: 200,
              body: "image-bytes",
              headers: [{"content-type", "image/jpeg"}]
            }

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
          "prompt" => "value of steps is 4 and value of answer is 10, give in valid json",
          "url" => "https://fastly.picsum.photos/id/145/200/300.jpg?hmac=abc",
          "model" => "gpt-4o",
          "response_format" => %{
            "type" => "json_schema",
            "json_schema" => %{
              "name" => "schemaing",
              "strict" => true,
              "schema" => %{
                "type" => "object",
                "properties" => %{
                  "steps" => %{"type" => "string"},
                  "answer" => %{"type" => "string"}
                },
                "required" => ["steps", "answer"],
                "additionalProperties" => false
              }
            }
          }
        }

        assert "I'm sorry, but I can't provide the information from the document." =
                 Dispatcher.dispatch("parse_via_gpt_vision", fields)
      end
    end

    test "downloads the image and sends it inline as base64" do
      with_mock(Messages, validate_media: fn _, _ -> %{is_valid: true, message: "success"} end) do
        image_bytes = <<137, 80, 78, 71, 13, 10, 26, 10>>

        Tesla.Mock.mock(fn
          %{method: :get, url: "https://example.com/image.png"} ->
            %Tesla.Env{status: 200, body: image_bytes, headers: [{"content-type", "image/png"}]}

          %{method: :post, url: "https://api.openai.com/v1/chat/completions", body: body} ->
            assert body =~ "data:image/png;base64,#{Base.encode64(image_bytes)}"
            refute body =~ "https://example.com/image.png"

            %Tesla.Env{
              status: 200,
              body: %{"choices" => [%{"message" => %{"content" => "{\"answer\": 10}"}}]}
            }
        end)

        fields = %{
          "prompt" => "what's the answer",
          "url" => "https://example.com/image.png",
          "model" => "gpt-4o",
          "organization_id" => "1",
          "response_format" => %{"type" => "json_object"}
        }

        assert %{success: true, response: %{"answer" => 10}} =
                 Dispatcher.dispatch("parse_via_gpt_vision", fields)
      end
    end

    test "routes to Failure when image download fails" do
      with_mock(Messages, validate_media: fn _, _ -> %{is_valid: true, message: "success"} end) do
        Tesla.Mock.mock(fn
          %{method: :get, url: "https://example.com/missing.png"} -> {:error, :timeout}
        end)

        fields = %{
          "prompt" => "what's the answer",
          "url" => "https://example.com/missing.png",
          "model" => "gpt-4o",
          "organization_id" => "1"
        }

        assert "Failed to download image for vision parsing" ==
                 Dispatcher.dispatch("parse_via_gpt_vision", fields)
      end
    end

    test "with invalid json_schema (OpenAI 400) returns the provider error" do
      with_mock(Messages, validate_media: fn _, _ -> %{is_valid: true, message: "success"} end) do
        Tesla.Mock.mock(fn
          %{method: :get} ->
            %Tesla.Env{
              status: 200,
              body: "image-bytes",
              headers: [{"content-type", "image/jpeg"}]
            }

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
          "prompt" => "value of steps is 4 and value of answer is 10, give in valid json",
          "url" => "https://fastly.picsum.photos/id/145/200/300.jpg?hmac=abc",
          "model" => "gpt-4o",
          "response_format" => %{
            "type" => "json_schema",
            "json_schema" => %{
              "name" => "schemaing",
              "strict" => true,
              "schema" => %{
                "type" => "object",
                "properties" => %{
                  "steps" => %{"type" => "string"},
                  "answer" => %{"type" => "string"}
                },
                "required" => ["steps", "answer"]
              }
            }
          }
        }

        assert "Invalid schema for response_format" <> _ =
                 Dispatcher.dispatch("parse_via_gpt_vision", fields)
      end
    end
  end
end
