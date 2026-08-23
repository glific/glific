defmodule Glific.AI.TelemetryTest do
  @moduledoc false
  use ExUnit.Case, async: false

  import Mock

  alias Glific.AI.Telemetry

  setup do
    original_config = Application.get_env(:glific, :ai_telemetry, [])

    on_exit(fn ->
      Application.put_env(:glific, :ai_telemetry, original_config)
      :telemetry.detach("glific-ai-appsignal")
    end)

    :ok
  end

  describe "attach/0 when disabled (the config/test.exs default)" do
    test "returns :ok without touching the OTel bridge" do
      Application.put_env(:glific, :ai_telemetry, enabled: false)

      with_mock ReqLLM.OpenTelemetry,
                [:passthrough],
                attach: fn _handler_id, _opts ->
                  flunk("must not attach the OTel bridge when disabled")
                end do
        assert :ok == Telemetry.attach()
      end
    end

    test "returns :ok when the config key is entirely absent" do
      Application.delete_env(:glific, :ai_telemetry)

      assert :ok == Telemetry.attach()
    end

    # AppSignal metrics are deliberately not gated on tracing config: they send no content
    # anywhere new and cost nothing, and an org that never signs up for Langfuse should still
    # see LLM health next to the rest of Glific's telemetry.
    test "still attaches the AppSignal handlers" do
      Application.put_env(:glific, :ai_telemetry, enabled: false)
      :telemetry.detach("glific-ai-appsignal")

      assert :ok == Telemetry.attach()

      assert Enum.any?(
               :telemetry.list_handlers([:req_llm, :request, :stop]),
               &(&1.id == "glific-ai-appsignal")
             )
    end
  end

  describe "attach/0 when enabled" do
    test "passes content: :none explicitly to the bridge" do
      Application.put_env(:glific, :ai_telemetry, enabled: true)

      with_mock ReqLLM.OpenTelemetry,
                [:passthrough],
                attach: fn _handler_id, opts ->
                  assert Keyword.get(opts, :content) == :none
                  assert Keyword.get(opts, :adapter) == Glific.AI.Telemetry.OTelAdapter
                  assert Keyword.get(opts, :langfuse) == true
                  :ok
                end do
        assert :ok == Telemetry.attach()
      end
    end

    test "treats {:error, :opentelemetry_unavailable} as a normal outcome, not a failure" do
      Application.put_env(:glific, :ai_telemetry, enabled: true)

      with_mock ReqLLM.OpenTelemetry,
                [:passthrough],
                attach: fn _handler_id, _opts -> {:error, :opentelemetry_unavailable} end do
        assert :ok == Telemetry.attach()
      end
    end

    test "treats {:error, :already_exists} as a normal outcome too" do
      Application.put_env(:glific, :ai_telemetry, enabled: true)

      with_mock ReqLLM.OpenTelemetry,
                [:passthrough],
                attach: fn _handler_id, _opts -> {:error, :already_exists} end do
        assert :ok == Telemetry.attach()
      end
    end
  end

  describe "prune_stale_spans/0" do
    test "returns a non-negative integer without raising, whether or not the bridge is attached" do
      assert Telemetry.prune_stale_spans() >= 0
    end
  end
end
