defmodule Glific.AI.Model.ReqLLMTest do
  use ExUnit.Case, async: true

  alias Glific.AI.Model.ReqLLM, as: ModelReqLLM
  alias Glific.AI.Model.Result
  alias ReqLLM.Context

  describe "request_opts/1 — :model" do
    test "returns an error when :model is missing" do
      assert {:error, :missing_model} = ModelReqLLM.request_opts(api_key: "sk-test")
    end

    test "passes the model spec through unchanged" do
      assert {:ok, "anthropic:claude-sonnet-5", _call_opts} =
               ModelReqLLM.request_opts(model: "anthropic:claude-sonnet-5")
    end

    test "drops :model and :cache_ttl from the forwarded call opts" do
      {:ok, _model, call_opts} =
        ModelReqLLM.request_opts(model: "anthropic:claude-sonnet-5", cache_ttl: "1h")

      refute Keyword.has_key?(call_opts, :model)
      refute Keyword.has_key?(call_opts, :cache_ttl)
    end
  end

  describe "request_opts/1 — temperature coercion" do
    test "coerces an integer temperature to a float" do
      {:ok, _model, call_opts} =
        ModelReqLLM.request_opts(model: "anthropic:claude-sonnet-5", temperature: 0)

      assert call_opts[:temperature] === 0.0
    end

    test "leaves a float temperature unchanged" do
      {:ok, _model, call_opts} =
        ModelReqLLM.request_opts(model: "anthropic:claude-sonnet-5", temperature: 0.7)

      assert call_opts[:temperature] === 0.7
    end

    test "does nothing when temperature is absent" do
      {:ok, _model, call_opts} = ModelReqLLM.request_opts(model: "anthropic:claude-sonnet-5")

      refute Keyword.has_key?(call_opts, :temperature)
    end
  end

  describe "request_opts/1 — receive_timeout clamping" do
    test "defaults to a value comfortably below the 45s step budget" do
      {:ok, _model, call_opts} = ModelReqLLM.request_opts(model: "anthropic:claude-sonnet-5")

      assert call_opts[:receive_timeout] < 45_000
    end

    test "clamps a caller-supplied timeout at or above 45s" do
      {:ok, _model, call_opts} =
        ModelReqLLM.request_opts(model: "anthropic:claude-sonnet-5", receive_timeout: 120_000)

      assert call_opts[:receive_timeout] < 45_000
    end

    test "clamps :infinity too" do
      {:ok, _model, call_opts} =
        ModelReqLLM.request_opts(model: "anthropic:claude-sonnet-5", receive_timeout: :infinity)

      assert call_opts[:receive_timeout] < 45_000
    end

    test "leaves a caller-supplied timeout under the cap alone" do
      {:ok, _model, call_opts} =
        ModelReqLLM.request_opts(model: "anthropic:claude-sonnet-5", receive_timeout: 10_000)

      assert call_opts[:receive_timeout] == 10_000
    end
  end

  describe "request_opts/1 — Anthropic prompt caching" do
    test "is turned on for an anthropic model" do
      {:ok, _model, call_opts} = ModelReqLLM.request_opts(model: "anthropic:claude-sonnet-5")

      assert call_opts[:provider_options][:anthropic_prompt_cache] == true
      assert call_opts[:provider_options][:anthropic_cache_messages] == -2
      refute Keyword.has_key?(call_opts[:provider_options], :anthropic_prompt_cache_ttl)
    end

    test "carries the skill's cache_ttl as anthropic_prompt_cache_ttl" do
      {:ok, _model, call_opts} =
        ModelReqLLM.request_opts(model: "anthropic:claude-sonnet-5", cache_ttl: "1h")

      assert call_opts[:provider_options][:anthropic_prompt_cache_ttl] == "1h"
    end

    test "is never sent to a non-Anthropic provider" do
      {:ok, _model, call_opts} = ModelReqLLM.request_opts(model: "google:gemini-2.5-pro")

      refute Keyword.has_key?(call_opts, :provider_options)
    end

    test "merges into provider_options the caller already set, rather than overwriting them" do
      {:ok, _model, call_opts} =
        ModelReqLLM.request_opts(
          model: "anthropic:claude-sonnet-5",
          provider_options: [anthropic_top_k: 5]
        )

      assert call_opts[:provider_options][:anthropic_top_k] == 5
      assert call_opts[:provider_options][:anthropic_prompt_cache] == true
    end

    test "does not blow up on an unresolvable model spec — caching is just skipped" do
      {:ok, _model, call_opts} = ModelReqLLM.request_opts(model: "not_a_real_provider:xyz")

      refute Keyword.has_key?(call_opts, :provider_options)
    end
  end

  describe "to_result/1" do
    test "normalises the message, and renames usage into Glific's own field names" do
      message = Context.assistant("The answer is 42.")

      response = %ReqLLM.Response{
        id: "resp_1",
        model: "claude-sonnet-5",
        context: Context.new([message]),
        message: message,
        finish_reason: :stop,
        usage: %{
          "input_tokens" => 120,
          "output_tokens" => 30,
          "cache_read_input_tokens" => 80,
          "cache_creation_input_tokens" => 15
        }
      }

      assert {:ok, %Result{} = result} = ModelReqLLM.to_result(response)

      assert result.message == message
      assert result.tool_calls == []
      assert result.finish_reason == :stop
      assert result.context == response.context

      assert result.usage == %{
               prompt: 120,
               completion: 30,
               cached: 80,
               cache_creation: 15
             }
    end

    test "returns an all-zero usage map when the response carries no usage" do
      message = Context.assistant("hi")

      response = %ReqLLM.Response{
        id: "resp_2",
        model: "claude-sonnet-5",
        context: Context.new([message]),
        message: message,
        finish_reason: :stop,
        usage: nil
      }

      assert {:ok, %Result{usage: usage}} = ModelReqLLM.to_result(response)
      assert usage == Result.zero_usage()
    end

    test "is an error when the response carries no assistant message" do
      response = %ReqLLM.Response{
        id: "resp_3",
        model: "claude-sonnet-5",
        context: Context.new([]),
        message: nil
      }

      assert {:error, :no_message_returned} = ModelReqLLM.to_result(response)
    end
  end

  describe "chat/2 and object/3 — no network call is made for a request ReqLLM can reject locally" do
    test "chat/2 surfaces an unresolvable model as a logged, string error" do
      assert {:error, message} =
               ModelReqLLM.chat(Context.new([Context.user("hi")]),
                 model: "not_a_real_provider:xyz",
                 api_key: "sk-test"
               )

      assert is_binary(message)
    end

    test "object/3 surfaces an unresolvable model as a logged, string error" do
      assert {:error, message} =
               ModelReqLLM.object(
                 Context.new([Context.user("hi")]),
                 [answer: [type: :string, required: true]],
                 model: "not_a_real_provider:xyz",
                 api_key: "sk-test"
               )

      assert is_binary(message)
    end
  end
end
