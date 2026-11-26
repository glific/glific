defmodule Glific.Flows.Webhooks.ChainProgressTest do
  use Glific.DataCase, async: false

  alias Glific.{Fixtures, Flows.WebhookLog, Flows.Webhooks.ChainProgress, Flows.Webhooks.VoiceSts}

  setup %{organization_id: organization_id} do
    flow = Fixtures.flow_fixture(%{organization_id: organization_id})

    {:ok, log} =
      WebhookLog.create_webhook_log(%{
        url: "voice-filesearch-gpt",
        method: "FUNCTION",
        request_headers: %{},
        flow_id: flow.id,
        organization_id: organization_id
      })

    %{log: log}
  end

  defp callback(log, index, message, extra \\ %{}) do
    Map.merge(
      %{
        "webhook_log_id" => log.id,
        "organization_id" => log.organization_id,
        "webhook_name" => "voice-filesearch-gpt",
        "call_type" => "voice_sts",
        "block_index" => index,
        "total_blocks" => 3,
        "message" => message,
        "output_type" => if(index == 3, do: "audio", else: "text"),
        "kaapi_dispatch_ts" => 1_000_000
      },
      extra
    )
  end

  test "only a successful non-final block is intermediate" do
    assert ChainProgress.intermediate?(%{"success" => true}, %{
             "block_index" => 1,
             "total_blocks" => 3
           })

    refute ChainProgress.intermediate?(%{"success" => true}, %{
             "block_index" => 3,
             "total_blocks" => 3
           })

    refute ChainProgress.intermediate?(%{"success" => false}, %{
             "block_index" => 2,
             "total_blocks" => 3
           })

    refute ChainProgress.intermediate?(%{"success" => true}, %{})
  end

  test "intermediate blocks are stashed and appended to the webhook log",
       %{log: log, organization_id: organization_id} do
    ChainProgress.record_intermediate(organization_id, callback(log, 1, "namaste"), 1_500_000)

    ChainProgress.record_intermediate(
      organization_id,
      callback(log, 2, "answer", %{"thread_id" => "conv_1"}),
      2_500_000
    )

    steps = Repo.get(WebhookLog, log.id).response_json["intermediate_callbacks"]

    assert [
             %{"component" => "stt", "latency_ms" => 500.0},
             %{"component" => "llm", "latency_ms" => 1000}
           ] = steps

    assert %{"stt" => "namaste", "text" => "answer", "thread_id" => "conv_1"} =
             ChainProgress.take(organization_id, log.id)
  end

  test "final block is logged and steps survive the log rewrite",
       %{log: log, organization_id: organization_id} do
    ChainProgress.record_intermediate(organization_id, callback(log, 1, "hello"), 1_500_000)

    ChainProgress.record_final(
      %{"success" => true},
      callback(log, 3, "https://x/a.ogg", %{"callback_received_ts" => 3_000_000})
    )

    message = ChainProgress.keep_steps(log.id, %{success: true, message: "https://x/a.ogg"})
    assert [%{"component" => "stt"}, %{"component" => "tts"}] = message.intermediate_callbacks
    assert %{transcript: "hello", media_url: "https://x/a.ogg"} = message
  end

  test "final callback merges the stashed answer and transcript",
       %{log: log, organization_id: organization_id} do
    ChainProgress.record_intermediate(organization_id, callback(log, 1, "hello"), 1_500_000)

    ChainProgress.record_intermediate(
      organization_id,
      callback(log, 2, "the answer", %{"thread_id" => "conv_9"}),
      2_000_000
    )

    response = callback(log, 3, "https://x/a.ogg", %{"success" => true})

    shaped =
      VoiceSts.handle_callback(%{"success" => true}, response, %{
        organization_id: organization_id
      })

    assert %{
             "message" => "the answer",
             "translated_text" => "the answer",
             "transcript" => "hello",
             "media_url" => "https://x/a.ogg",
             "thread_id" => "conv_9"
           } = shaped
  end

  test "failure callback passes through untouched", %{log: log, organization_id: organization_id} do
    response = %{"success" => false, "reason" => "boom", "webhook_log_id" => log.id}

    assert VoiceSts.handle_callback(%{"success" => false}, response, %{
             organization_id: organization_id
           }) == response
  end

  test "a repeated block delivery is logged once", %{log: log, organization_id: organization_id} do
    block = callback(log, 1, "hello")
    ChainProgress.record_intermediate(organization_id, block, 1_500_000)
    ChainProgress.record_intermediate(organization_id, block, 1_600_000)

    assert [_one] = Repo.get(WebhookLog, log.id).response_json["intermediate_callbacks"]
  end

  test "a failure after the LLM answered falls back to text",
       %{log: log, organization_id: organization_id} do
    ChainProgress.record_intermediate(organization_id, callback(log, 1, "hello"), 1_500_000)

    ChainProgress.record_intermediate(
      organization_id,
      callback(log, 2, "the answer", %{"thread_id" => "conv_2"}),
      2_000_000
    )

    failed = %{
      "call_type" => "voice_sts",
      "organization_id" => organization_id,
      "webhook_log_id" => log.id
    }

    shaped = ChainProgress.fallback_to_text(%{"success" => false}, failed)

    assert %{
             "success" => true,
             "tts_failed" => true,
             "message" => "the answer",
             "media_url" => nil,
             "thread_id" => "conv_2"
           } = shaped

    assert VoiceSts.handle_callback(%{"success" => false}, shaped, %{
             organization_id: organization_id
           }) == shaped
  end

  test "a failure before the LLM answered stays a failure",
       %{log: log, organization_id: organization_id} do
    ChainProgress.record_intermediate(organization_id, callback(log, 1, "hello"), 1_500_000)

    failed = %{
      "call_type" => "voice_sts",
      "organization_id" => organization_id,
      "webhook_log_id" => log.id
    }

    assert ChainProgress.fallback_to_text(%{"success" => false}, failed) == failed
  end

  test "a failed GCS upload fails the node with its reason and logs a failed tts step",
       %{log: log, organization_id: organization_id} do
    ChainProgress.record_intermediate(organization_id, callback(log, 1, "hello"), 1_500_000)
    ChainProgress.record_intermediate(organization_id, callback(log, 2, "answer"), 2_000_000)

    final =
      log
      |> callback(nil, nil, %{"callback_received_ts" => 3_000_000})
      |> Map.merge(%{"success" => false, "reason" => "GCS upload failed"})

    ChainProgress.record_final(%{"success" => true}, final)

    assert ChainProgress.fallback_to_text(%{"success" => true}, final) == final

    assert VoiceSts.handle_callback(%{"success" => true}, final, %{
             organization_id: organization_id
           }) == final

    steps = Repo.get(WebhookLog, log.id).response_json["intermediate_callbacks"]

    assert %{"block_index" => 3, "status" => "failure", "error" => "GCS upload failed"} =
             List.last(steps)

    message = ChainProgress.keep_steps(log.id, %{success: false, message: nil})
    assert %{media_url: nil, message: nil, transcript: "hello"} = message
  end

  test "a failed block without an index is logged as the next block",
       %{log: log, organization_id: organization_id} do
    ChainProgress.record_intermediate(organization_id, callback(log, 1, "hello"), 1_500_000)

    failed =
      log
      |> callback(nil, nil, %{"callback_received_ts" => 2_000_000})
      |> Map.delete("block_index")

    ChainProgress.record_final(%{"success" => false, "error" => "llm down"}, failed)

    assert [_, %{"block_index" => 2, "component" => "llm", "status" => "failure"}] =
             Repo.get(WebhookLog, log.id).response_json["intermediate_callbacks"]
  end
end
