defmodule Glific.Flows.Webhooks.NmtTtsWithBhasiniTest do
  @moduledoc """
  End-to-end regression tests for the `nmt_tts_with_bhasini` synchronous FUNCTION webhook.

  Covers:
  1. Happy path: Gemini NMT+TTS returns success → job updates FlowContext results →
     flow resumes on the success branch and sends the media_url as a message.
  2. Failure: Gemini NMT+TTS returns error → job calls wakeup_one with Failure →
     flow resumes on the failure branch and sends the "failure" message.
  """

  use GlificWeb.ConnCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  import Mock

  alias Glific.{
    Fixtures,
    Flows.Action,
    Flows.Flow,
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

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Creates a FlowContext already in await state (is_await_result: true), linked
  # to the real call_and_wait flow so that wakeup_one can resume execution and
  # send the expected message to the contact.
  defp build_context(organization_id) do
    contact = Fixtures.contact_fixture(%{organization_id: organization_id})
    flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})
    [node | _] = flow.nodes

    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: contact.id,
        flow_id: flow.id,
        flow_uuid: flow.uuid,
        uuid_map: %{},
        organization_id: organization_id,
        wakeup_at: DateTime.add(DateTime.utc_now(), 60),
        is_await_result: true,
        node_uuid: node.uuid
      })

    {Repo.preload(context, [:contact, :flow]), contact, flow}
  end

  # ---------------------------------------------------------------------------
  # Helpers — poll for the message the flow sends after the Oban job completes.
  # These are SYNCHRONOUS FUNCTION webhooks: wakeup_one runs inside perform/1
  # (not via a TaskSupervisor task), so Oban.drain_queue is sufficient to
  # synchronise; no TaskSupervisor wait is needed.
  # ---------------------------------------------------------------------------

  @await_attempts 50
  @await_interval_ms 100

  defp await_flow_message(contact_id, expected_body) do
    await_flow_message(contact_id, expected_body, @await_attempts)
  end

  defp await_flow_message(contact_id, expected_body, 0) do
    flunk("Timed out waiting for message #{inspect(expected_body)} for contact #{contact_id}")
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

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "nmt_tts_with_bhasini" do
    test "happy path: Gemini NMT+TTS returns success — flow resumes on success branch", %{
      organization_id: organization_id
    } do
      {context, contact, flow} = build_context(organization_id)

      expected_media_url =
        "https://storage.googleapis.com/mock-bucket/Gemini/outbound/mock.mp3"

      action = %Action{
        method: "FUNCTION",
        url: "nmt_tts_with_bhasini",
        headers: %{},
        # result_name must match what the call_and_wait flow sends:
        # the success node uses @results.filesearch.message
        result_name: "filesearch",
        body:
          Jason.encode!(%{
            text: "Hello",
            source_language: "english",
            target_language: "hindi",
            organization_id: organization_id
          })
      }

      with_mock(Gemini, [:passthrough],
        nmt_text_to_speech: fn _org_id, _text, _src, _dst, _opts ->
          %{
            success: true,
            media_url: expected_media_url,
            # Include message so @results.filesearch.message resolves in the flow
            message: expected_media_url,
            translated_text: "नमस्ते"
          }
        end
      ) do
        assert Webhook.execute(action, context) == nil

        [job] = all_enqueued(worker: Webhook, prefix: "global")
        assert job.priority == 2

        Oban.drain_queue(queue: :gpt_webhook_queue)
      end

      # WebhookLog assertions — preserved from original tests
      flow_filter = %{
        flow_id: flow.id,
        contact_id: contact.id,
        organization_id: organization_id
      }

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_filter}))
      assert log.status == "Success"
      assert log.response_json["success"] == true
      assert log.response_json["media_url"] != nil

      # End-to-end flow assertion: after the Oban job runs and wakeup_one resumes
      # the call_and_wait flow, the success branch sends @results.filesearch.message
      # which resolves to the media_url we mocked.
      message = await_flow_message(contact.id, expected_media_url)
      assert message.body == expected_media_url
    end

    test "failure: Gemini NMT+TTS returns error — flow resumes on failure branch", %{
      organization_id: organization_id
    } do
      {context, contact, flow} = build_context(organization_id)

      action = %Action{
        method: "FUNCTION",
        url: "nmt_tts_with_bhasini",
        headers: %{},
        result_name: "filesearch",
        body:
          Jason.encode!(%{
            text: "Hello",
            source_language: "english",
            target_language: "hindi",
            organization_id: organization_id
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

      # WebhookLog assertions — preserved from original tests
      flow_filter = %{
        flow_id: flow.id,
        contact_id: contact.id,
        organization_id: organization_id
      }

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_filter}))
      assert log != nil
      assert log.error != nil or log.status_code >= 400

      # End-to-end flow assertion: failure result causes wakeup_one to fire with
      # the "Failure" temp message, routing the call_and_wait flow to the failure
      # branch, which sends the literal "failure" message.
      message = await_flow_message(contact.id, "failure")
      assert message.body == "failure"
    end
  end
end
