defmodule Glific.AI.Telemetry.OTelAdapterTest do
  use ExUnit.Case, async: true

  alias Glific.AI.Telemetry.Context
  alias Glific.AI.Telemetry.OTelAdapter

  # One row per key `req_llm` is documented to attach only under opt-in content capture — see
  # ReqLLM.OpenTelemetry.Adapter and Glific.AI.Telemetry.OTelAdapter's moduledoc. Adding a new
  # leak-prone key later means adding one row here.
  @denied_keys [
    "gen_ai.input.messages",
    "gen_ai.output.messages",
    "gen_ai.system_instructions",
    "gen_ai.tool.definitions",
    "gen_ai.tool.call.arguments",
    "gen_ai.tool.call.result"
  ]

  describe "allowed_attributes/1 — denied keys" do
    for denied_key <- @denied_keys do
      test "drops #{denied_key}" do
        attributes = %{
          unquote(denied_key) => "sensitive content",
          "gen_ai.usage.input_tokens" => 12
        }

        filtered = OTelAdapter.allowed_attributes(attributes)

        refute Map.has_key?(filtered, unquote(denied_key))
        assert filtered["gen_ai.usage.input_tokens"] == 12
      end
    end

    test "drops denied keys even when given as atoms (as req_llm's translator sends them)" do
      attributes = Map.new(@denied_keys, &{String.to_atom(&1), "sensitive content"})

      assert OTelAdapter.allowed_attributes(attributes) == %{}
    end

    test "drops an unrecognized key rather than failing closed loudly" do
      attributes = %{"some.future.req_llm.attribute" => "unreviewed"}

      assert OTelAdapter.allowed_attributes(attributes) == %{}
    end
  end

  describe "allowed_attributes/1 — allow-listed keys survive" do
    @allowed %{
      "gen_ai.usage.input_tokens" => 10,
      "gen_ai.usage.output_tokens" => 20,
      "gen_ai.request.model" => "gpt-5",
      "gen_ai.request.temperature" => 0.7,
      "gen_ai.response.finish_reasons" => ["stop"],
      "gen_ai.operation.name" => "chat",
      "gen_ai.provider.name" => "openai",
      "gen_ai.conversation.id" => "thread-1",
      "gen_ai.output.type" => "text",
      "gen_ai.tool.name" => "search_contacts",
      "gen_ai.tool.call.id" => "call-1",
      "gen_ai.tool.type" => "builtin",
      "server.address" => "api.openai.com",
      "server.port" => 443,
      "error.type" => "timeout",
      "http.response.status_code" => "429",
      "langfuse.observation.cost_details" => "{}",
      "langfuse.user.id" => "42",
      "langfuse.session.id" => "99",
      "glific.organization_id" => 1,
      "ai.skill" => "chatbot_diagnose"
    }

    test "every allow-listed key survives filtering" do
      filtered = OTelAdapter.allowed_attributes(@allowed)

      assert filtered == @allowed
    end

    test "atom-keyed allow-listed attributes survive too" do
      attributes = Map.new(@allowed, fn {key, value} -> {String.to_atom(key), value} end)

      filtered = OTelAdapter.allowed_attributes(attributes)

      assert map_size(filtered) == map_size(attributes)
    end
  end

  describe "allowed_attributes/1 — a builtin tool's arguments do not leak via a sibling key" do
    test "gen_ai.tool.name survives while gen_ai.tool.call.arguments on the same map is dropped" do
      attributes = %{
        "gen_ai.tool.name" => "web_search",
        "gen_ai.tool.type" => "builtin",
        "gen_ai.tool.call.id" => "call-1",
        "gen_ai.tool.call.arguments" => ~s({"query" => "beneficiary phone number"})
      }

      filtered = OTelAdapter.allowed_attributes(attributes)

      assert filtered == %{
               "gen_ai.tool.name" => "web_search",
               "gen_ai.tool.type" => "builtin",
               "gen_ai.tool.call.id" => "call-1"
             }
    end
  end

  describe "start_span/3 caller-context injection (merge_context/1)" do
    setup do
      on_exit(fn -> Context.clear() end)
    end

    # start_span/3 itself hands the merged map straight to the real OTel SDK adapter, whose
    # return value is an opaque span term with no public accessor for "what attributes did you
    # get" — so this exercises merge_context/1, the exact function start_span/3 calls to build
    # that map, rather than reimplementing its logic here.
    test "injects the caller context as namespaced span attributes" do
      Context.put(%{
        organization_id: 1,
        user_id: 2,
        request_id: "req-1",
        skill: "chatbot_diagnose",
        step_index: 3,
        conversation_id: 4
      })

      merged = OTelAdapter.merge_context(%{"gen_ai.request.model" => "gpt-5"})

      assert merged["glific.organization_id"] == 1
      assert merged["glific.user_id"] == 2
      assert merged["glific.conversation_id"] == 4
      assert merged["ai.request_id"] == "req-1"
      assert merged["ai.skill"] == "chatbot_diagnose"
      assert merged["ai.step_index"] == 3
      assert merged["langfuse.user.id"] == 2
      assert merged["langfuse.session.id"] == 4
      assert merged["gen_ai.request.model"] == "gpt-5"
    end

    test "drops nil context values instead of emitting null attributes" do
      Context.put(%{organization_id: 1})

      merged = OTelAdapter.merge_context(%{})

      assert merged == %{"glific.organization_id" => 1}
      refute Map.has_key?(merged, "glific.user_id")
      refute Map.has_key?(merged, "ai.request_id")
    end

    test "with no context set at all, only the caller's own attributes are present" do
      merged = OTelAdapter.merge_context(%{"gen_ai.request.model" => "gpt-5"})

      assert merged == %{"gen_ai.request.model" => "gpt-5"}
    end
  end

  describe "start_span/3 against the real OTel SDK" do
    setup do
      on_exit(fn -> Context.clear() end)
    end

    test "returns a span without raising, with context merged in" do
      Context.put(%{organization_id: 1, skill: "chatbot_diagnose"})

      span = OTelAdapter.start_span("chat gpt-5", %{"gen_ai.request.model" => "gpt-5"}, [])

      refute is_nil(span)
    end
  end

  # ReqLLM.Telemetry.OpenTelemetry.request_start/2 folds request-side content into the *start*
  # span's attributes, which never reach set_attributes/3. Filtering only there would leave the
  # prompt unguarded the moment anyone flips `content: :attributes`.
  describe "start_span/3 redaction" do
    setup do
      on_exit(fn -> Context.clear() end)
    end

    for denied <- [
          "gen_ai.input.messages",
          "gen_ai.system_instructions",
          "gen_ai.tool.definitions"
        ] do
      test "drops #{denied} before it reaches the tracer" do
        attributes = %{unquote(denied) => "beneficiary data", "gen_ai.request.model" => "gpt-5"}

        filtered = OTelAdapter.allowed_attributes(attributes)

        refute Map.has_key?(filtered, unquote(denied))
        assert Map.has_key?(filtered, "gen_ai.request.model")
      end
    end

    test "keeps the caller context it merges in afterwards" do
      Context.put(%{organization_id: 1, user_id: 2, skill: "echo"})

      merged =
        %{"gen_ai.input.messages" => "beneficiary data"}
        |> OTelAdapter.allowed_attributes()
        |> OTelAdapter.merge_context()

      refute Map.has_key?(merged, "gen_ai.input.messages")
      assert merged["glific.organization_id"] == 1
      assert merged["ai.skill"] == "echo"
    end
  end
end
