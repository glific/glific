defmodule Glific.Flows.Webhooks.SpeechToTextWithBhasiniTest do
  @moduledoc """
  End-to-end regression tests for the `speech_to_text_with_bhasini` synchronous FUNCTION webhook.

  Covers:
  1. Happy path: Gemini STT succeeds → job updates FlowContext results → flow resumes on
     the success branch (the call_and_wait success node fires, confirming the Success route).
  2. Failure: Gemini STT returns 500 → job records error in WebhookLog → flow resumes on
     the failure branch and sends the "failure" message.
  """

  use GlificWeb.ConnCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Flows.Action,
    Flows.Flow,
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

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Creates a FlowContext already in await state (is_await_result: true), linked
  # to the real call_and_wait flow so that wakeup_one can resume execution and
  # route to the correct success/failure branch.
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

  describe "speech_to_text_with_bhasini" do
    test "happy path: Gemini STT succeeds — flow resumes on success branch", %{
      organization_id: organization_id
    } do
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

      {context, contact, flow} = build_context(organization_id)

      action = %Action{
        method: "FUNCTION",
        url: "speech_to_text_with_bhasini",
        headers: %{},
        # result_name must match what the call_and_wait flow references:
        # the success node sends @results.filesearch.message
        result_name: "filesearch",
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

      # WebhookLog assertions — preserved from original tests
      flow_filter = %{
        flow_id: flow.id,
        contact_id: contact.id,
        organization_id: organization_id
      }

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_filter}))
      assert log != nil
      assert log.status == "Success"
      assert log.response_json["success"] == true
      assert log.response_json["asr_response_text"] != nil

      # End-to-end flow assertion: the Oban job stored %{asr_response_text: "..."}
      # under the "filesearch" result key and called wakeup_one with "Success".
      # The call_and_wait router sees "Success" → success node fires with
      # @results.filesearch.message. Since the STT result has no "message" key,
      # the parser leaves the variable unresolved — but the contact DID receive
      # a message on the success branch (distinct from the "failure" string).
      message = await_flow_message(contact.id, "@results.filesearch.message")
      assert message.body == "@results.filesearch.message"
    end

    test "failure: Gemini returns 500 — WebhookLog records error and flow sends failure message",
         %{organization_id: organization_id} do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{status: 200, body: "fake_audio_bytes"}

        %{method: :post} ->
          %Tesla.Env{status: 500, body: %{}}
      end)

      {context, contact, flow} = build_context(organization_id)

      action = %Action{
        method: "FUNCTION",
        url: "speech_to_text_with_bhasini",
        headers: %{},
        result_name: "filesearch",
        body:
          Jason.encode!(%{
            speech: "https://gcs.example.com/audio.ogg",
            contact: %{"id" => contact.id}
          })
      }

      assert Webhook.execute(action, context) == nil
      Oban.drain_queue(queue: :gpt_webhook_queue)

      # WebhookLog assertions — preserved from original tests
      flow_filter = %{
        flow_id: flow.id,
        contact_id: contact.id,
        organization_id: organization_id
      }

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_filter}))
      assert log != nil
      assert log.error != nil or log.status_code >= 400

      # End-to-end flow assertion: the 500 Gemini response makes wakeup_one fire
      # with the "Failure" temp message, routing the call_and_wait flow to the
      # failure branch, which sends the literal "failure" message.
      message = await_flow_message(contact.id, "failure")
      assert message.body == "failure"
    end
  end
end
