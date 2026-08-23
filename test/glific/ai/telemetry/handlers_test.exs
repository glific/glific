defmodule Glific.AI.Telemetry.HandlersTest do
  use ExUnit.Case, async: false

  import Mock

  alias Glific.AI.Telemetry.Context
  alias Glific.AI.Telemetry.Handlers

  setup do
    Handlers.attach()

    on_exit(fn ->
      :telemetry.detach("glific-ai-appsignal")
      Context.clear()
    end)

    :ok
  end

  describe "handle_event/4 never raises" do
    test "[:req_llm, :request, :stop] with full metadata" do
      metadata = %{
        provider: :openai,
        model: %{id: "gpt-5"},
        finish_reason: :stop,
        usage: %{input_tokens: 10, output_tokens: 20, total_tokens: 30}
      }

      assert :ok ==
               :telemetry.execute([:req_llm, :request, :stop], %{duration: 1_000_000}, metadata)
    end

    test "[:req_llm, :request, :stop] with a completely empty metadata map" do
      assert :ok == :telemetry.execute([:req_llm, :request, :stop], %{}, %{})
    end

    test "[:req_llm, :request, :exception] with a malformed/partial metadata map" do
      assert :ok ==
               :telemetry.execute([:req_llm, :request, :exception], %{duration: nil}, %{
                 provider: :openai
               })
    end

    test "[:req_llm, :token_usage] with full measurements" do
      measurements = %{
        tokens: %{input_tokens: 5, output_tokens: 5, total_tokens: 10},
        cost: 0.01
      }

      assert :ok ==
               :telemetry.execute([:req_llm, :token_usage], measurements, %{model: %{id: "gpt-5"}})
    end

    test "[:req_llm, :token_usage] with malformed measurements" do
      assert :ok == :telemetry.execute([:req_llm, :token_usage], %{tokens: "not a map"}, %{})
    end

    test "[:req_llm, :request, :retry]" do
      assert :ok ==
               :telemetry.execute([:req_llm, :request, :retry], %{duration: 500}, %{
                 provider: :anthropic
               })
    end

    test "an unhandled req_llm event is a silent no-op" do
      assert :ok == :telemetry.execute([:req_llm, :reasoning, :start], %{}, %{})
    end
  end

  describe "reported tags" do
    test "carry provider, model, finish_reason, organization_id and skill — never payload data" do
      Context.put(%{organization_id: 7, skill: "chatbot_diagnose"})

      metadata = %{
        provider: :openai,
        model: %{id: "gpt-5"},
        finish_reason: :stop,
        usage: %{input_tokens: 10, output_tokens: 20, total_tokens: 30},
        request_payload: %{should: :never_be_read}
      }

      with_mock Elixir.Appsignal,
                [:passthrough],
                add_distribution_value: fn _name, _value, _tags -> :ok end,
                increment_counter: fn _name, _value, _tags -> :ok end do
        :telemetry.execute([:req_llm, :request, :stop], %{duration: 1_000_000}, metadata)

        assert called(
                 Elixir.Appsignal.add_distribution_value("ai_request_duration", :_, %{
                   provider: "openai",
                   model: "gpt-5",
                   finish_reason: "stop",
                   organization_id: "7",
                   skill: "chatbot_diagnose"
                 })
               )
      end
    end

    test "fall back to \"unknown\" for missing provider/model/finish_reason/context" do
      with_mock Elixir.Appsignal,
                [:passthrough],
                increment_counter: fn _name, _value, _tags -> :ok end do
        :telemetry.execute([:req_llm, :request, :retry], %{duration: 1}, %{})

        assert called(
                 Elixir.Appsignal.increment_counter("ai_request_retry_count", 1, %{
                   provider: "unknown",
                   model: "unknown",
                   finish_reason: "unknown",
                   organization_id: "unknown",
                   skill: "unknown"
                 })
               )
      end
    end
  end
end
