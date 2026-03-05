defmodule Glific.ThirdParty.Kaapi.SttTtsWorkerTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo
  import Tesla.Mock

  alias Glific.{
    Fixtures,
    Flows.FlowContext,
    Partners,
    Repo
  }

  alias Glific.ThirdParty.Kaapi.SttTtsWorker

  @org_id 1
  @api_key "sk_test_key"

  setup do
    {:ok, _credential} =
      Partners.create_credential(%{
        organization_id: @org_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{"api_key" => @api_key},
        is_active: true
      })

    Partners.get_organization!(@org_id) |> Partners.fill_cache()
    :ok
  end

  defp build_job_args(webhook_name, extra_fields \\ %{}) do
    contact = Fixtures.contact_fixture()
    webhook_log = Fixtures.webhook_log_fixture(%{organization_id: @org_id})

    fields =
      Map.merge(
        %{
          "speech" => "https://example.com/audio.wav",
          "text" => "Hello world",
          "organization_id" => @org_id,
          "flow_id" => 1,
          "contact_id" => contact.id,
          "webhook_log_id" => webhook_log.id,
          "result_name" => "response"
        },
        extra_fields
      )

    %{
      webhook_name: webhook_name,
      fields: fields,
      webhook_log_id: webhook_log.id,
      context_id: 0,
      organization_id: @org_id
    }
  end

  describe "enqueue/5" do
    test "enqueues a job successfully and returns {:ok, job}" do
      contact = Fixtures.contact_fixture()
      webhook_log = Fixtures.webhook_log_fixture(%{organization_id: @org_id})

      assert {:ok, _job} =
               SttTtsWorker.enqueue(
                 "speech_to_text",
                 %{"organization_id" => @org_id, "flow_id" => 1, "contact_id" => contact.id},
                 webhook_log.id,
                 0,
                 @org_id
               )
    end
  end

  describe "perform/1 — speech_to_text" do
    test "returns :ok when Kaapi acknowledges STT request (success: true)" do
      mock(fn
        %Tesla.Env{method: :get} -> %Tesla.Env{status: 200, body: "audio_bytes"}

        %Tesla.Env{method: :post} ->
          %Tesla.Env{status: 200, body: %{"job_id" => "stt-123", "status" => "queued"}}
      end)

      args = build_job_args("speech_to_text")

      assert :ok =
               perform_job(SttTtsWorker, args)
    end

    test "returns :ok and wakes flow with Failure on Kaapi STT error response" do
      contact = Fixtures.contact_fixture()
      webhook_log = Fixtures.webhook_log_fixture(%{organization_id: @org_id})

      flow = Glific.Flows.Flow.get_loaded_flow(@org_id, "published", %{keyword: "call_and_wait"})
      [node | _] = flow.nodes

      {:ok, context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          organization_id: @org_id,
          wakeup_at: DateTime.add(DateTime.utc_now(), 60),
          is_await_result: true,
          node_uuid: node.uuid
        })

      mock(fn
        %Tesla.Env{method: :get} -> %Tesla.Env{status: 404, body: "not found"}
      end)

      args = %{
        webhook_name: "speech_to_text",
        fields: %{
          "speech" => "https://example.com/missing.wav",
          "organization_id" => @org_id,
          "flow_id" => flow.id,
          "contact_id" => contact.id,
          "webhook_log_id" => webhook_log.id,
          "result_name" => "response"
        },
        webhook_log_id: webhook_log.id,
        context_id: context.id,
        organization_id: @org_id
      }

      assert :ok = perform_job(SttTtsWorker, args)

      # Flow context should no longer be in await state
      updated = Repo.get!(FlowContext, context.id)
      assert updated.is_await_result == false
    end

    test "snoozes when rate limit is exceeded" do
      # Exhaust ExRated bucket for this org
      organization = Partners.organization(@org_id)
      rate_key = "kaapi_stt_tts:#{organization.shortcode}"

      for _ <- 1..10 do
        ExRated.check_rate(rate_key, 60_000, 10)
      end

      args = build_job_args("speech_to_text")

      assert {:snooze, 5} = perform_job(SttTtsWorker, args)

      # Reset for other tests
      ExRated.delete_bucket(rate_key)
    end
  end

  describe "perform/1 — text_to_speech" do
    test "returns :ok when Kaapi acknowledges TTS request" do
      mock(fn
        %Tesla.Env{method: :post} ->
          %Tesla.Env{status: 200, body: %{"job_id" => "tts-456", "status" => "queued"}}
      end)

      args = build_job_args("text_to_speech")

      assert :ok = perform_job(SttTtsWorker, args)
    end

    test "wakes flow with Failure on Kaapi TTS service error" do
      contact = Fixtures.contact_fixture()
      webhook_log = Fixtures.webhook_log_fixture(%{organization_id: @org_id})

      flow = Glific.Flows.Flow.get_loaded_flow(@org_id, "published", %{keyword: "call_and_wait"})
      [node | _] = flow.nodes

      {:ok, context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          organization_id: @org_id,
          wakeup_at: DateTime.add(DateTime.utc_now(), 60),
          is_await_result: true,
          node_uuid: node.uuid
        })

      mock(fn
        %Tesla.Env{method: :post} ->
          %Tesla.Env{status: 503, body: %{"error" => "service unavailable"}}
      end)

      args = %{
        webhook_name: "text_to_speech",
        fields: %{
          "text" => "Hello",
          "organization_id" => @org_id,
          "flow_id" => flow.id,
          "contact_id" => contact.id,
          "webhook_log_id" => webhook_log.id,
          "result_name" => "response"
        },
        webhook_log_id: webhook_log.id,
        context_id: context.id,
        organization_id: @org_id
      }

      assert :ok = perform_job(SttTtsWorker, args)

      updated = Repo.get!(FlowContext, context.id)
      assert updated.is_await_result == false
    end
  end
end
