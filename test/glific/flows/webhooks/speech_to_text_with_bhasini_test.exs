defmodule Glific.Flows.Webhooks.SpeechToTextWithBhasiniTest do
  use Glific.DataCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Flows.Action,
    Flows.FlowContext,
    Flows.Webhook,
    Flows.WebhookLog,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    :ok
  end

  defp build_context(attrs) do
    contact = Fixtures.contact_fixture(attrs)

    flow_attrs = %{
      flow_id: 1,
      flow_uuid: Ecto.UUID.generate(),
      contact_id: contact.id,
      organization_id: attrs.organization_id
    }

    {:ok, context} = FlowContext.create_flow_context(flow_attrs)
    {Repo.preload(context, [:contact, :flow]), flow_attrs, contact}
  end

  describe "speech_to_text_with_bhasini" do
    test "happy path returns success with asr_response_text", attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{status: 200, body: "fake_audio_bytes"}

        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{
              candidates: [
                %{content: %{parts: [%{text: Jason.encode!("transcribed speech text")}]}}
              ],
              usageMetadata: %{totalTokenCount: 10}
            }
          }
      end)

      {context, flow_attrs, contact} = build_context(attrs)

      action = %Action{
        method: "FUNCTION",
        url: "speech_to_text_with_bhasini",
        headers: %{},
        body:
          Jason.encode!(%{
            speech: "https://gcs.example.com/audio.ogg",
            contact: %{"id" => contact.id}
          })
      }

      assert Webhook.execute(action, context) == nil

      [%{priority: 0, queue: "gpt_webhook_queue"} | _] =
        all_enqueued(worker: Webhook, prefix: "global")

      Oban.drain_queue(queue: :gpt_webhook_queue)

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log != nil
      assert log.status == "Success"
      assert log.response_json["success"] == true
      assert log.response_json["asr_response_text"] != nil
    end

    test "failure - Gemini returns 500 sets error on webhook log", attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{status: 200, body: "fake_audio_bytes"}

        %{method: :post} ->
          %Tesla.Env{status: 500, body: %{}}
      end)

      {context, flow_attrs, contact} = build_context(attrs)

      action = %Action{
        method: "FUNCTION",
        url: "speech_to_text_with_bhasini",
        headers: %{},
        body:
          Jason.encode!(%{
            speech: "https://gcs.example.com/audio.ogg",
            contact: %{"id" => contact.id}
          })
      }

      assert Webhook.execute(action, context) == nil
      Oban.drain_queue(queue: :gpt_webhook_queue)

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log != nil
      assert log.error != nil or log.status_code >= 400
    end
  end
end
