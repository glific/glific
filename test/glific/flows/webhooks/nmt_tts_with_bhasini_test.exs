defmodule Glific.Flows.Webhooks.NmtTtsWithBhasiniTest do
  use Glific.DataCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  import Mock

  alias Glific.{
    Fixtures,
    Flows.Action,
    Flows.FlowContext,
    Flows.Webhook,
    Flows.WebhookLog,
    Partners,
    Repo,
    Seeds.SeedsDev,
    ThirdParty.Gemini
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)

    # GCS credentials are required for nmt_tts_with_bhasini — the webhook
    # checks organization.services["google_cloud_storage"] before calling Gemini.
    {:ok, _credential} =
      Partners.create_credential(%{
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
      })

    Partners.get_organization!(1) |> Partners.fill_cache()
    :ok
  end

  defp build_context(attrs) do
    flow_attrs = %{
      flow_id: 1,
      flow_uuid: Ecto.UUID.generate(),
      contact_id: Fixtures.contact_fixture(attrs).id,
      organization_id: attrs.organization_id
    }

    {:ok, context} = FlowContext.create_flow_context(flow_attrs)
    {Repo.preload(context, [:contact, :flow]), flow_attrs}
  end

  describe "nmt_tts_with_bhasini" do
    test "happy path: Gemini NMT+TTS returns success with media_url", attrs do
      {context, flow_attrs} = build_context(attrs)

      action = %Action{
        method: "FUNCTION",
        url: "nmt_tts_with_bhasini",
        headers: %{},
        body:
          Jason.encode!(%{
            text: "Hello",
            source_language: "english",
            target_language: "hindi",
            organization_id: attrs.organization_id
          })
      }

      with_mock(Gemini, [:passthrough],
        nmt_text_to_speech: fn _org_id, _text, _src, _dst, _opts ->
          %{
            success: true,
            media_url: "https://storage.googleapis.com/mock-bucket/Gemini/outbound/mock.mp3",
            translated_text: "नमस्ते"
          }
        end
      ) do
        assert Webhook.execute(action, context) == nil

        [job] = all_enqueued(worker: Webhook, prefix: "global")
        assert job.priority == 2

        Oban.drain_queue(queue: :gpt_webhook_queue)
      end

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log.status == "Success"
      assert log.response_json["success"] == true
      assert log.response_json["media_url"] != nil
    end

    test "failure: Gemini NMT+TTS returns error, log records failure", attrs do
      {context, flow_attrs} = build_context(attrs)

      action = %Action{
        method: "FUNCTION",
        url: "nmt_tts_with_bhasini",
        headers: %{},
        body:
          Jason.encode!(%{
            text: "Hello",
            source_language: "english",
            target_language: "hindi",
            organization_id: attrs.organization_id
          })
      }

      with_mock(Gemini, [:passthrough],
        nmt_text_to_speech: fn _org_id, _text, _src, _dst, _opts ->
          %{success: false, reason: "Gemini TTS upstream error", media_url: nil, translated_text: "Hello"}
        end
      ) do
        assert Webhook.execute(action, context) == nil
        Oban.drain_queue(queue: :gpt_webhook_queue)
      end

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log != nil
      assert log.error != nil or log.status_code >= 400
    end
  end
end
