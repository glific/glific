defmodule Glific.Flows.Webhooks.KaapiChainTest do
  use Glific.DataCase, async: false

  import Mock

  alias Glific.{Fixtures, Flows.WebhookLog, Flows.Webhooks.KaapiChain}

  setup %{organization_id: organization_id} do
    %{log: Fixtures.webhook_log_fixture(%{organization_id: organization_id})}
  end

  defp callback(log, index, message, extra \\ %{}) do
    Map.merge(
      %{
        "webhook_log_id" => log.id,
        "organization_id" => log.organization_id,
        "webhook_name" => "voice-filesearch-gpt",
        "call_type" => "voice_sts",
        "chain_blocks" => ["stt", "llm", "tts"],
        "audio_size_bucket" => "0-1MB",
        "block_index" => index,
        "total_blocks" => 3,
        "message" => message,
        "output_type" => if(index == 3, do: "audio", else: "text"),
        "kaapi_dispatch_ts" => 1_000_000
      },
      extra
    )
  end

  defp steps(log), do: Repo.get(WebhookLog, log.id).response_json["intermediate_callbacks"]

  defp capture_distributions(fun) do
    test_pid = self()

    with_mock Appsignal, [:passthrough],
      add_distribution_value: fn name, value, tags ->
        send(test_pid, {:distribution, name, value, tags})
        :ok
      end do
      fun.()
    end
  end

  describe "intermediate?/2" do
    test "only a successful non-final block is intermediate" do
      assert KaapiChain.intermediate?(%{"success" => true}, %{
               "block_index" => 1,
               "total_blocks" => 3
             })

      refute KaapiChain.intermediate?(%{"success" => true}, %{
               "block_index" => 3,
               "total_blocks" => 3
             })

      refute KaapiChain.intermediate?(%{"success" => false}, %{
               "block_index" => 2,
               "total_blocks" => 3
             })

      refute KaapiChain.intermediate?(%{"success" => true}, %{})
    end
  end

  describe "record_intermediate/2" do
    test "appends each block with its component and the gap since the previous callback",
         %{log: log} do
      KaapiChain.record_intermediate(callback(log, 1, "namaste"), 1_500_000)

      KaapiChain.record_intermediate(
        callback(log, 2, "answer", %{"thread_id" => "conv_1"}),
        2_500_000
      )

      assert [
               %{
                 "block_index" => 1,
                 "component" => "stt",
                 "status" => "success",
                 "message" => "namaste",
                 "latency_ms" => 500.0
               },
               %{
                 "block_index" => 2,
                 "component" => "llm",
                 "thread_id" => "conv_1",
                 "latency_ms" => 1000
               }
             ] = steps(log)
    end

    test "a repeated delivery of a block is logged once", %{log: log} do
      block = callback(log, 1, "hello")
      KaapiChain.record_intermediate(block, 1_500_000)
      KaapiChain.record_intermediate(block, 1_600_000)

      assert [_one] = steps(log)
    end

    test "names blocks by position when the caller did not name them", %{log: log} do
      log
      |> callback(1, "hello")
      |> Map.delete("chain_blocks")
      |> KaapiChain.record_intermediate(1_500_000)

      assert [%{"component" => "block_1"}] = steps(log)
    end

    test "skips the latency when the dispatch stamp is missing", %{log: log} do
      log
      |> callback(1, "hello")
      |> Map.delete("kaapi_dispatch_ts")
      |> KaapiChain.record_intermediate(1_500_000)

      assert [%{"latency_ms" => nil}] = steps(log)
    end

    test "a callback without a webhook log id is ignored" do
      assert :ok = KaapiChain.record_intermediate(%{"block_index" => 1}, 1_500_000)
    end

    test "emits kaapi_chain_latency tagged by chain, component and status", %{log: log} do
      capture_distributions(fn ->
        KaapiChain.record_intermediate(callback(log, 1, "hello"), 1_500_000)
      end)

      assert_received {:distribution, "kaapi_chain_latency", 500.0,
                       %{
                         chain: "voice_sts",
                         component: "stt",
                         status: "success",
                         size_bucket: "0-1MB",
                         webhook_name: "voice-filesearch-gpt"
                       }}
    end
  end

  describe "record_final/2" do
    test "logs a final callback without a block index as the next block", %{log: log} do
      KaapiChain.record_intermediate(callback(log, 1, "hello"), 1_500_000)
      KaapiChain.record_intermediate(callback(log, 2, "answer"), 2_000_000)

      final =
        log
        |> callback(nil, "https://x/a.ogg", %{"callback_received_ts" => 3_000_000})
        |> Map.put("output_type", "audio")

      KaapiChain.record_final(%{"success" => true}, final)

      assert %{"block_index" => 3, "component" => "tts", "status" => "success"} =
               List.last(steps(log))
    end

    test "logs a failed block with its error and a failure latency", %{log: log} do
      KaapiChain.record_intermediate(callback(log, 1, "hello"), 1_500_000)

      failed =
        log
        |> callback(nil, nil, %{"callback_received_ts" => 2_000_000})
        |> Map.delete("block_index")

      capture_distributions(fn ->
        KaapiChain.record_final(%{"success" => false, "error" => "llm down"}, failed)
      end)

      assert [
               _,
               %{
                 "block_index" => 2,
                 "component" => "llm",
                 "status" => "failure",
                 "error" => "llm down",
                 "message" => nil
               }
             ] = steps(log)

      assert_received {:distribution, "kaapi_chain_latency", 500.0,
                       %{component: "llm", status: "failure"}}
    end

    test "a GCS upload failure on a successful Kaapi callback is logged as a failure",
         %{log: log} do
      KaapiChain.record_intermediate(callback(log, 1, "hello"), 1_500_000)
      KaapiChain.record_intermediate(callback(log, 2, "answer"), 2_000_000)

      final =
        log
        |> callback(nil, nil, %{"callback_received_ts" => 3_000_000})
        |> Map.merge(%{"success" => false, "reason" => "GCS upload failed"})

      KaapiChain.record_final(%{"success" => true}, final)

      assert %{"block_index" => 3, "status" => "failure", "error" => "GCS upload failed"} =
               List.last(steps(log))
    end

    test "a retried index-less failure is logged once", %{log: log} do
      KaapiChain.record_intermediate(callback(log, 1, "hello"), 1_500_000)

      failed =
        log
        |> callback(nil, nil, %{"callback_received_ts" => 2_000_000})
        |> Map.delete("block_index")

      KaapiChain.record_final(%{"success" => false, "error" => "llm down"}, failed)
      KaapiChain.record_final(%{"success" => false, "error" => "llm down"}, failed)

      assert [%{"component" => "stt"}, %{"component" => "llm", "final" => true}] = steps(log)
    end

    test "ignores a response that is not part of a chain", %{log: log} do
      assert :ok =
               KaapiChain.record_final(%{"success" => true}, %{"webhook_log_id" => log.id})

      assert steps(log) == nil
    end
  end

  describe "outputs/1" do
    test "returns the last text and audio, the conversation id and each block's output",
         %{log: log} do
      KaapiChain.record_intermediate(callback(log, 1, "hello"), 1_500_000)

      KaapiChain.record_intermediate(
        callback(log, 2, "answer", %{"thread_id" => "conv_1"}),
        2_000_000
      )

      KaapiChain.record_final(
        %{"success" => true},
        callback(log, nil, "https://x/a.ogg", %{
          "callback_received_ts" => 3_000_000,
          "output_type" => "audio"
        })
      )

      assert %{
               "text" => "answer",
               "audio" => "https://x/a.ogg",
               "thread_id" => "conv_1",
               "blocks" => %{"stt" => "hello", "llm" => "answer", "tts" => "https://x/a.ogg"}
             } = KaapiChain.outputs(log.id)
    end

    test "leaves failed blocks out", %{log: log} do
      KaapiChain.record_intermediate(callback(log, 1, "hello"), 1_500_000)

      KaapiChain.record_final(
        %{"success" => false, "error" => "boom"},
        callback(log, nil, nil, %{"callback_received_ts" => 2_000_000})
      )

      assert %{"text" => "hello", "blocks" => blocks} = KaapiChain.outputs(log.id)
      assert blocks == %{"stt" => "hello"}
    end

    test "is empty without a webhook log" do
      assert KaapiChain.outputs(nil) == %{"blocks" => %{}}
    end
  end

  describe "fallback_to_text/2" do
    defp failed_final(log), do: Map.merge(callback(log, nil, nil), %{"chain_fallback" => "llm"})

    test "resumes an opted-in chain with the last text when a later block fails",
         %{log: log} do
      KaapiChain.record_intermediate(callback(log, 1, "hello"), 1_500_000)
      KaapiChain.record_intermediate(callback(log, 2, "the answer"), 2_000_000)

      assert %{
               "success" => true,
               "chain_degraded" => true,
               "message" => "the answer",
               "output_type" => "text"
             } = KaapiChain.fallback_to_text(%{"success" => false}, failed_final(log))
    end

    test "an LLM failure after a successful STT stays a failure, not the transcript",
         %{log: log} do
      KaapiChain.record_intermediate(callback(log, 1, "hello"), 1_500_000)
      response = failed_final(log)

      assert KaapiChain.fallback_to_text(%{"success" => false}, response) == response
    end

    test "stays a failure when no block produced text", %{log: log} do
      response = failed_final(log)
      assert KaapiChain.fallback_to_text(%{"success" => false}, response) == response
    end

    test "stays a failure for a chain that did not opt in", %{log: log} do
      KaapiChain.record_intermediate(callback(log, 2, "the answer"), 2_000_000)
      response = callback(log, nil, nil)

      assert KaapiChain.fallback_to_text(%{"success" => false}, response) == response
    end

    test "leaves a successful Kaapi result alone, even with a failed upload", %{log: log} do
      KaapiChain.record_intermediate(callback(log, 2, "the answer"), 2_000_000)
      response = Map.put(failed_final(log), "success", false)

      assert KaapiChain.fallback_to_text(%{"success" => true}, response) == response
    end
  end

  describe "ended?/1" do
    test "is true once the block that ended the chain is logged", %{log: log} do
      KaapiChain.record_intermediate(callback(log, 1, "hello"), 1_500_000)
      refute KaapiChain.ended?(callback(log, nil, nil))

      KaapiChain.record_final(
        %{"success" => false, "error" => "boom"},
        callback(log, nil, nil, %{"callback_received_ts" => 2_000_000})
      )

      assert KaapiChain.ended?(callback(log, nil, nil))
    end

    test "is false for a response that is not part of a chain", %{log: log} do
      refute KaapiChain.ended?(%{"webhook_log_id" => log.id})
    end
  end

  describe "append_callback_result/2" do
    test "adds the steps, answer, media_url and conversation id to a successful log message",
         %{log: log} do
      KaapiChain.record_intermediate(callback(log, 1, "hello"), 1_500_000)

      KaapiChain.record_intermediate(
        callback(log, 2, "answer", %{"thread_id" => "conv_1"}),
        2_000_000
      )

      KaapiChain.record_final(
        %{"success" => true},
        callback(log, nil, "https://x/a.ogg", %{
          "callback_received_ts" => 3_000_000,
          "output_type" => "audio"
        })
      )

      message =
        KaapiChain.append_callback_result(log.id, %{success: true, message: "https://x/a.ogg"})

      assert %{
               message: "answer",
               media_url: "https://x/a.ogg",
               thread_id: "conv_1",
               outputs: %{"stt" => "hello", "llm" => "answer", "tts" => "https://x/a.ogg"}
             } = message

      assert length(message.intermediate_callbacks) == 3
    end

    test "keeps a failed log message's own message and reason", %{log: log} do
      KaapiChain.record_intermediate(callback(log, 1, "hello"), 1_500_000)

      message =
        KaapiChain.append_callback_result(log.id, %{
          success: false,
          message: nil,
          reason: "GCS upload failed"
        })

      assert %{message: nil, media_url: nil, reason: "GCS upload failed"} = message
    end

    test "returns the message untouched without steps or a log", %{log: log} do
      assert KaapiChain.append_callback_result(log.id, %{success: true}) == %{success: true}
      assert KaapiChain.append_callback_result(nil, %{success: true}) == %{success: true}
    end
  end
end
