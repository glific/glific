defmodule Glific.Flows.Webhooks.ParseViaGptVisionTest do
  use Glific.DataCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Flows.Action,
    Flows.Flow,
    Flows.FlowContext,
    Flows.Webhook,
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

  # ---------------------------------------------------------------------------
  # Flow message polling helpers
  #
  # For synchronous webhooks, the flow resumes inside Oban.drain_queue, so
  # the message is already in the DB when drain returns. We poll briefly to
  # handle any in-process scheduling latency.
  # ---------------------------------------------------------------------------

  @await_attempts 50
  @await_interval_ms 100

  defp await_flow_message(contact_id, expected_body) do
    await_flow_message(contact_id, expected_body, @await_attempts)
  end

  defp await_flow_message(_contact_id, expected_body, 0) do
    flunk("Timed out waiting for message #{inspect(expected_body)}")
  end

  defp await_flow_message(contact_id, expected_body, attempts) do
    case Glific.Messages.list_messages(%{
           filter: %{contact_id: contact_id},
           opts: %{limit: 1, order: :desc}
         }) do
      [%{body: ^expected_body} = msg | _] ->
        msg

      _ ->
        Process.sleep(@await_interval_ms)
        await_flow_message(contact_id, expected_body, attempts - 1)
    end
  end
end
