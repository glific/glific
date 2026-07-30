defmodule Glific.Flows.Webhooks.VoiceLatencyTest do
  @moduledoc """
  Unit tests for the voice-node latency instrumentation (issue #5290): file-size bucketing and
  the per-component (`stt`/`filesearch`/`tts`) distributions emitted for a voice callback.
  """
  use ExUnit.Case, async: false

  import Mock

  alias Glific.Flows.Webhooks.Instrumentation

  @mb 1_000_000

  describe "size_bucket/1" do
    test "buckets by the issue's file-size ranges" do
      assert Instrumentation.size_bucket(0) == "0-1MB"
      assert Instrumentation.size_bucket(@mb - 1) == "0-1MB"
      assert Instrumentation.size_bucket(@mb) == "1-5MB"
      assert Instrumentation.size_bucket(5 * @mb - 1) == "1-5MB"
      assert Instrumentation.size_bucket(5 * @mb) == "5-10MB"
      assert Instrumentation.size_bucket(10 * @mb) == "10-20MB"
      assert Instrumentation.size_bucket(20 * @mb) == "20MB+"
      assert Instrumentation.size_bucket(100 * @mb) == "20MB+"
    end

    test "nil / negative size buckets as unknown (never silently 0-1MB)" do
      assert Instrumentation.size_bucket(nil) == "unknown"
      assert Instrumentation.size_bucket(-1) == "unknown"
    end
  end

  # Captures Appsignal.add_distribution_value/3 and increment_counter/3 calls for assertions.
  defp capture(fun) do
    test_pid = self()

    with_mock Appsignal, [:passthrough],
      add_distribution_value: fn name, value, tags ->
        send(test_pid, {:distribution, name, value, tags})
        :ok
      end,
      increment_counter: fn name, value, tags ->
        send(test_pid, {:counter, name, value, tags})
        :ok
      end do
      fun.()
    end

    drain(%{distributions: [], counters: []})
  end

  defp drain(acc) do
    receive do
      {:distribution, name, value, tags} ->
        drain(%{acc | distributions: acc.distributions ++ [{name, value, tags}]})

      {:counter, name, value, tags} ->
        drain(%{acc | counters: acc.counters ++ [{name, value, tags}]})
    after
      0 -> acc
    end
  end

  defp component(distributions, name),
    do:
      Enum.find(distributions, fn
        {"voice_component_latency", _value, %{component: ^name}} -> true
        _ -> false
      end)

  describe "record_voice_latencies/4" do
    test "emits filesearch and tts components tagged by size bucket (no total — that's kaapi_llm_latency)" do
      # 500ms filesearch round-trip (arrival - dispatch, microseconds).
      response = %{
        "webhook_name" => "voice-filesearch-gpt",
        "audio_size_bucket" => "1-5MB",
        "kaapi_dispatch_ts" => 1_000_000,
        "callback_received_ts" => 1_500_000
      }

      %{distributions: distributions} =
        capture(fn -> Instrumentation.record_voice_latencies(response, 200, "success") end)

      assert {"voice_component_latency", 500.0, filesearch_tags} =
               component(distributions, "filesearch")

      assert filesearch_tags == %{
               webhook_name: "voice-filesearch-gpt",
               component: "filesearch",
               size_bucket: "1-5MB",
               status: "success"
             }

      assert {"voice_component_latency", 200, _tts_tags} = component(distributions, "tts")

      # the end-to-end total lives in kaapi_llm_latency, not here
      refute Enum.any?(distributions, fn {name, _v, _t} -> name == "voice_node_latency" end)
    end

    test "skips filesearch (no counter) when the round-trip stamps are absent (deploy window)" do
      response = %{"webhook_name" => "voice-filesearch-gpt", "audio_size_bucket" => "0-1MB"}

      %{distributions: distributions, counters: counters} =
        capture(fn -> Instrumentation.record_voice_latencies(response, 50, "success") end)

      assert component(distributions, "filesearch") == nil
      # absent stamps are not skew, so no unusable-stamp counter
      assert counters == []
    end

    test "counts a skewed round-trip (arrival < dispatch) and drops the filesearch component" do
      response = %{
        "webhook_name" => "voice-filesearch-gpt",
        "audio_size_bucket" => "5-10MB",
        # arrival precedes dispatch -> clock skew
        "kaapi_dispatch_ts" => 2_000_000,
        "callback_received_ts" => 1_000_000
      }

      %{distributions: distributions, counters: counters} =
        capture(fn -> Instrumentation.record_voice_latencies(response, 50, "success") end)

      assert component(distributions, "filesearch") == nil

      assert {"voice_filesearch_stamp_unusable", 1, %{webhook_name: "voice-filesearch-gpt"}} =
               hd(counters)
    end

    test "nil tts (failure callback) skips the tts component instead of emitting a synthetic 0" do
      response = %{
        "webhook_name" => "voice-filesearch-gpt",
        "audio_size_bucket" => "unknown",
        "kaapi_dispatch_ts" => 2_000_000,
        "callback_received_ts" => 2_400_000
      }

      %{distributions: distributions} =
        capture(fn -> Instrumentation.record_voice_latencies(response, nil, "failure") end)

      assert component(distributions, "tts") == nil

      assert {"voice_component_latency", 400.0, %{status: "failure"}} =
               component(distributions, "filesearch")
    end

    test "tts_status tags the tts component distinctly from the node status" do
      response = %{
        "webhook_name" => "voice-filesearch-gpt",
        "audio_size_bucket" => "1-5MB",
        "kaapi_dispatch_ts" => 1_000_000,
        "callback_received_ts" => 1_400_000
      }

      # Node succeeded (text-only degradation), but TTS itself failed.
      %{distributions: distributions} =
        capture(fn ->
          Instrumentation.record_voice_latencies(response, 50, "success", "failure")
        end)

      assert {"voice_component_latency", 50, %{status: "failure"}} =
               component(distributions, "tts")

      assert {"voice_component_latency", _fs, %{status: "success"}} =
               component(distributions, "filesearch")
    end

    test "an emit failure is logged, never raised (the observational guarantee)" do
      response = %{
        "webhook_name" => "voice-filesearch-gpt",
        "audio_size_bucket" => "1-5MB",
        "kaapi_dispatch_ts" => 1_000_000,
        "callback_received_ts" => 1_400_000
      }

      # A raising AppSignal client must not propagate out of the metric emit into the parked flow.
      with_mock Appsignal, [:passthrough],
        add_distribution_value: fn _name, _value, _tags -> raise "appsignal boom" end,
        increment_counter: fn _name, _value, _tags -> :ok end do
        assert Instrumentation.record_voice_latencies(response, 50, "success") == :ok
      end
    end
  end
end
