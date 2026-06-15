defmodule Glific.Flows.Webhooks.AsyncSupportTest do
  @moduledoc """
  Unit tests for `Glific.Flows.Webhooks.AsyncSupport` — the shared plumbing behind the
  four async Kaapi webhook implementations (STT, TTS, unified-llm, unified-voice-llm).

  Focuses on branches NOT exercised by the end-to-end callback tests: the immediate
  Kaapi-not-active failure path, and the happy path that creates the webhook log, parks
  the flow, and enqueues the worker.
  """
  use Glific.DataCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  import Glific.WebhookTestHelpers

  alias Glific.Flows.{Action, WebhookLog}
  alias Glific.Flows.Webhooks.AsyncSupport
  alias Glific.{Fixtures, Partners}
  alias Glific.ThirdParty.Kaapi.SttTtsWorker

  # Adds an active "kaapi" credential with the given secrets and refreshes the org cache
  # so AsyncSupport's `Kaapi.fetch_kaapi_creds/1` can read it.
  defp kaapi_credential(secrets) do
    {:ok, _} =
      Partners.create_credential(%{
        organization_id: 1,
        shortcode: "kaapi",
        keys: %{},
        secrets: secrets,
        is_active: true
      })

    Partners.get_organization!(1) |> Partners.fill_cache()
  end

  defp stt_action do
    %Action{
      headers: %{"Content-Type" => "application/json"},
      method: "FUNCTION",
      url: "speech_to_text",
      body: Jason.encode!(%{"speech" => "https://gcs.example.com/audio.ogg"}),
      result_name: "response",
      wait_time: 60
    }
  end

  defp llm_action do
    %Action{
      headers: %{"Content-Type" => "application/json"},
      method: "FUNCTION",
      url: "filesearch-gpt",
      body: Jason.encode!(%{"question" => "hello"}),
      result_name: "response",
      wait_time: 60
    }
  end

  describe "enqueue_stt_tts/3" do
    test "returns an immediate failure and logs when Kaapi is not active", %{
      organization_id: org_id
    } do
      contact = Fixtures.contact_fixture(%{organization_id: org_id})
      {context, _attrs} = build_flow_context(org_id, contact.id)

      assert {:ok, returned, [failure_msg]} =
               AsyncSupport.enqueue_stt_tts(stt_action(), context, "speech_to_text")

      assert returned.id == context.id
      assert failure_msg.body == "Failure"
      refute_enqueued(worker: SttTtsWorker, prefix: "global")

      log = List.first(WebhookLog.list_webhook_logs(%{filter: %{organization_id: org_id}}))
      assert log.error == "Kaapi is not active"
    end

    test "parks the flow and enqueues the worker when Kaapi is active", %{
      organization_id: org_id
    } do
      kaapi_credential(%{"api_key" => "sk_test_key"})
      contact = Fixtures.contact_fixture(%{organization_id: org_id})
      {context, _attrs} = build_flow_context(org_id, contact.id)

      assert {:wait, parked, []} =
               AsyncSupport.enqueue_stt_tts(stt_action(), context, "speech_to_text")

      assert parked.is_await_result == true
      assert_enqueued(worker: SttTtsWorker, prefix: "global")
    end
  end

  describe "unified_llm_and_wait/3" do
    test "returns an immediate failure when Kaapi has no api_key", %{organization_id: org_id} do
      # credential exists but carries no api_key — falls through to the not-active branch
      kaapi_credential(%{})
      contact = Fixtures.contact_fixture(%{organization_id: org_id})
      {context, _attrs} = build_flow_context(org_id, contact.id)

      assert {:ok, returned, [failure_msg]} =
               AsyncSupport.unified_llm_and_wait(llm_action(), context, "unified-llm-call")

      assert returned.id == context.id
      assert failure_msg.body == "Failure"

      log = List.first(WebhookLog.list_webhook_logs(%{filter: %{organization_id: org_id}}))
      assert log.error == "Kaapi is not active"
    end
  end
end
