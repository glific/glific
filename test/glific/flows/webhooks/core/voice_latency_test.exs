defmodule Glific.Flows.Webhooks.VoiceLatencyTest do
  @moduledoc """
  Unit tests for the voice-node latency instrumentation (issue #5290): file-size bucketing and
  the per-component (`stt`/`filesearch`/`tts`) + total distributions emitted for a voice callback.
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

  # Captures every Appsignal.add_distribution_value/3 call as {name, value, tags} for assertions.
  defp capture_distributions(fun) do
    test_pid = self()

    with_mock Appsignal, [:passthrough],
      add_distribution_value: fn name, value, tags ->
        send(test_pid, {:distribution, name, value, tags})
        :ok
      end do
      fun.()
    end

    collect_distributions([])
  end

  defp collect_distributions(acc) do
    receive do
      {:distribution, name, value, tags} -> collect_distributions([{name, value, tags} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  describe "record_voice_latencies/3" do
    test "emits filesearch, tts and total tagged by size bucket, with total = stt + fs + tts" do
      # 500ms filesearch round-trip (arrival - dispatch, microseconds).
      response = %{
        "webhook_name" => "voice-filesearch-gpt",
        "audio_size_bucket" => "1-5MB",
        "stt_latency_ms" => 300,
        "kaapi_dispatch_ts" => 1_000_000,
        "callback_received_ts" => 1_500_000
      }

      distributions =
        capture_distributions(fn ->
          Instrumentation.record_voice_latencies(response, 200, "success")
        end)

      filesearch = find_component(distributions, "filesearch")
      tts = find_component(distributions, "tts")
      total = Enum.find(distributions, fn {name, _v, _t} -> name == "voice_node_latency" end)

      assert {"voice_component_latency", 500.0, fs_tags} = filesearch

      assert fs_tags == %{
               webhook_name: "voice-filesearch-gpt",
               component: "filesearch",
               size_bucket: "1-5MB",
               status: "success"
             }

      assert {"voice_component_latency", 200, _tts_tags} = tts

      # total = stt (300) + filesearch (500) + tts (200)
      assert {"voice_node_latency", 1000.0, total_tags} = total

      assert total_tags == %{
               webhook_name: "voice-filesearch-gpt",
               size_bucket: "1-5MB",
               status: "success"
             }
    end

    test "skips filesearch (and excludes it from total) when the round-trip stamps are absent" do
      response = %{
        "webhook_name" => "voice-filesearch-gpt",
        "audio_size_bucket" => "0-1MB",
        "stt_latency_ms" => 100
      }

      distributions =
        capture_distributions(fn ->
          Instrumentation.record_voice_latencies(response, 50, "success")
        end)

      assert find_component(distributions, "filesearch") == nil

      total = Enum.find(distributions, fn {name, _v, _t} -> name == "voice_node_latency" end)
      # total = stt (100) + tts (50), no filesearch
      assert {"voice_node_latency", 150, _tags} = total
    end

    test "records failure status (e.g. Kaapi failure, no TTS) with defaulted bucket" do
      response = %{"kaapi_dispatch_ts" => 2_000_000, "callback_received_ts" => 2_400_000}

      distributions =
        capture_distributions(fn ->
          Instrumentation.record_voice_latencies(response, 0, "failure")
        end)

      total = Enum.find(distributions, fn {name, _v, _t} -> name == "voice_node_latency" end)
      assert {"voice_node_latency", 400.0, tags} = total
      assert tags.status == "failure"
      assert tags.size_bucket == "unknown"
    end
  end

  defp find_component(distributions, component) do
    Enum.find(distributions, fn
      {"voice_component_latency", _value, %{component: ^component}} -> true
      _ -> false
    end)
  end
end
