defmodule Glific.AI.CodecTest do
  use ExUnit.Case, async: true

  alias Glific.AI.Codec
  alias ReqLLM.Context
  alias ReqLLM.Message
  alias ReqLLM.Message.ContentPart
  alias ReqLLM.Message.ReasoningDetails
  alias ReqLLM.ToolCall

  describe "round trip via ReqLLM's own constructors" do
    test "user text message" do
      assert_round_trips(Context.user("why is this contact stuck?"))
    end

    test "system message" do
      assert_round_trips(Context.system("You rewrite WhatsApp templates."))
    end

    test "assistant text message" do
      assert_round_trips(Context.assistant("The contact is waiting at a webhook node."))
    end

    test "assistant with a single tool call" do
      calls = [%{id: "call_1", name: "query_org_data", arguments: %{"table" => "flow_contexts"}}]
      assert_round_trips(Context.assistant("Let me look.", tool_calls: calls))
    end

    test "assistant with parallel tool calls" do
      calls = [
        %{id: "call_1", name: "query_org_data", arguments: %{"table" => "flow_contexts"}},
        %{id: "call_2", name: "query_org_data", arguments: %{"table" => "contact_histories"}},
        %{id: "call_3", name: "describe_table", arguments: %{"table" => "flow_results"}}
      ]

      assert_round_trips(Context.assistant("", tool_calls: calls))
    end

    test "tool result message" do
      assert_round_trips(Context.tool_result("call_1", ~s({"rows":14})))
    end

    test "unicode and emoji survive" do
      assert_round_trips(Context.user("नमस्ते 🙏 — क्या यह टेम्पलेट ठीक है?"))
    end

    test "a large tool result survives" do
      assert_round_trips(Context.tool_result("call_1", String.duplicate("row,", 50_000)))
    end
  end

  describe "the fields that live outside content" do
    test "thinking signature survives the round trip" do
      message = %Message{
        role: :assistant,
        content: [%ContentPart{type: :thinking, text: "The category looks promotional."}],
        reasoning_details: [
          %ReasoningDetails{
            text: "The category looks promotional.",
            signature: "ErUBCkYIBBgCKkDsig==",
            encrypted?: true,
            provider: :anthropic,
            format: "anthropic-claude-v1",
            index: 0,
            provider_data: %{"kind" => "thinking"}
          }
        ]
      }

      {:ok, decoded} = round_trip(message)

      [detail] = decoded.reasoning_details
      assert detail.signature == "ErUBCkYIBBgCKkDsig=="
      assert detail.encrypted? == true
      assert detail.provider == :anthropic
      assert detail.format == "anthropic-claude-v1"
      assert detail.provider_data == %{"kind" => "thinking"}
      assert decoded == message
    end

    test "thinking text alone, with no signature, still round trips" do
      message = %Message{
        role: :assistant,
        content: [%ContentPart{type: :thinking, text: "Considering the variable count."}],
        reasoning_details: nil
      }

      assert {:ok, ^message} = round_trip(message)
    end

    test "tool_calls survive as ToolCall structs" do
      message = %Message{
        role: :assistant,
        content: [],
        tool_calls: [
          %ToolCall{
            id: "call_9",
            type: "function",
            function: %{name: "query_org_data", arguments: ~s({"limit":5})}
          }
        ]
      }

      {:ok, decoded} = round_trip(message)
      assert [%ToolCall{id: "call_9", type: "function"}] = decoded.tool_calls
      assert decoded == message
    end

    test "function keys come back as atoms, because ReqLLM dot-accesses them" do
      message =
        Context.assistant("",
          tool_calls: [
            %{id: "call_1", name: "query_org_data", arguments: %{"table" => "flow_contexts"}}
          ]
        )

      {:ok, decoded} = round_trip(message)
      [%ToolCall{function: function}] = decoded.tool_calls

      assert Map.has_key?(function, :name)
      assert Map.has_key?(function, :arguments)
      refute Map.has_key?(function, "name")

      # ReqLLM's own encoder reaches for function.name; string keys would raise here, one turn
      # after the data was written.
      assert is_binary(Jason.encode!(decoded.tool_calls))
      assert is_binary(inspect(decoded.tool_calls))
    end

    test "non-utf8 attachment bytes survive base64 encoding" do
      bytes = <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10>>

      message = %Message{
        role: :user,
        content: [
          %ContentPart{type: :file, data: bytes, media_type: "image/jpeg", filename: "x.jpg"}
        ]
      }

      {:ok, encoded} = Codec.encode(message)
      assert {:ok, _json} = Jason.encode(encoded)

      {:ok, decoded} = round_trip(message)
      assert [%ContentPart{data: ^bytes}] = decoded.content
    end
  end

  describe "failure is loud" do
    test "an unknown content type is an error, not a dropped part" do
      message = %Message{role: :assistant, content: [%ContentPart{type: :hologram}]}
      assert {:error, {:unknown_part_type, :hologram}} = Codec.encode(message)
    end

    test "an unknown role is an error" do
      assert {:error, {:unknown_role, :oracle}} =
               Codec.encode(%Message{role: :oracle, content: []})
    end

    test "a future codec version is refused rather than guessed at" do
      assert {:error, {:unsupported_version, 99}} = Codec.decode(%{"v" => 99})
    end

    test "a map with no version is refused" do
      assert {:error, :missing_version} = Codec.decode(%{"role" => "user"})
    end

    test "a malformed tool call is an error" do
      encoded = %{
        "v" => Codec.version(),
        "role" => "assistant",
        "content" => [],
        "tool_calls" => [%{"nonsense" => true}]
      }

      assert {:error, {:malformed_tool_call, _}} = Codec.decode(encoded)
    end
  end

  describe "canonical form — normalise on the way in" do
    test "normalize/1 is idempotent" do
      message = %Message{
        role: :assistant,
        content: [%ContentPart{type: :text, text: "hi", metadata: %{step: 1, tags: [:a, :b]}}],
        metadata: %{latency_ms: 12, nested: %{provider: :openai}},
        tool_calls: [
          %ToolCall{id: "c1", type: "function", function: %{"name" => "t", "arguments" => "{}"}}
        ],
        reasoning_details: [%ReasoningDetails{text: "t", provider: :anthropic}]
      }

      once = Codec.normalize(message)
      assert Codec.normalize(once) == once
    end

    test "decode(encode(m)) equals normalize(m), whatever key types m arrived with" do
      message = %Message{
        role: :assistant,
        content: [%ContentPart{type: :text, text: "hi", metadata: %{step: 1}}],
        metadata: %{latency_ms: 12, nested: %{provider: :openai}},
        tool_calls: [
          %ToolCall{id: "c1", type: "function", function: %{"name" => "t", "arguments" => "{}"}}
        ],
        reasoning_details: [%ReasoningDetails{text: "t", provider: :anthropic, index: nil}]
      }

      {:ok, decoded} = round_trip(message)
      assert decoded == Codec.normalize(message)
    end

    test "free-form metadata keys become strings, function keys become atoms" do
      message = %Message{
        role: :assistant,
        content: [],
        metadata: %{latency_ms: 12},
        tool_calls: [
          %ToolCall{id: "c1", type: "function", function: %{"name" => "t", "arguments" => "{}"}}
        ]
      }

      normalized = Codec.normalize(message)

      assert normalized.metadata == %{"latency_ms" => 12}
      [%ToolCall{function: function}] = normalized.tool_calls
      assert %{name: "t", arguments: "{}"} = function
    end

    test "an already-canonical message is unchanged by normalisation" do
      message = Context.user("plain text turn")
      assert Codec.normalize(message) == message
    end

    test "a reasoning provider outside the known set is dropped, matching decode" do
      message = %Message{
        role: :assistant,
        content: [],
        reasoning_details: [%ReasoningDetails{text: "t", provider: :some_future_vendor}]
      }

      normalized = Codec.normalize(message)
      [detail] = normalized.reasoning_details
      assert detail.provider == nil

      {:ok, decoded} = round_trip(message)
      assert decoded == normalized
    end
  end

  describe "determinism, which prompt caching depends on" do
    test "encoding the same message twice produces byte-identical JSON" do
      {:ok, message} = one_message(Context.user("draft me a reminder template"))

      {:ok, first} = Codec.encode(message)
      {:ok, second} = Codec.encode(message)

      assert Jason.encode!(first) == Jason.encode!(second)
    end
  end

  describe "jsonb fidelity" do
    test "a full JSON encode/decode cycle preserves the message" do
      message = %Message{
        role: :assistant,
        content: [%ContentPart{type: :text, text: "done", metadata: %{"step" => 3}}],
        tool_call_id: "call_1",
        tool_calls: [
          %ToolCall{id: "call_1", type: "function", function: %{name: "noop", arguments: "{}"}}
        ],
        metadata: %{"latency_ms" => 1234},
        reasoning_details: [%ReasoningDetails{text: "t", signature: "sig", index: 2}]
      }

      {:ok, encoded} = Codec.encode(message)
      through_json = encoded |> Jason.encode!() |> Jason.decode!()

      assert {:ok, ^message} = Codec.decode(through_json)
    end
  end

  describe "context rebuild — the assertion the two-table design rests on" do
    test "an ordered set of encoded messages rebuilds an equivalent context" do
      original =
        Context.new([
          Context.system("You are a Glific assistant."),
          Context.user("why is contact 42 stuck?"),
          Context.assistant("Checking.",
            tool_calls: [
              %{id: "call_1", name: "query_org_data", arguments: %{"table" => "flow_contexts"}}
            ]
          ),
          Context.tool_result("call_1", ~s({"node":"webhook"})),
          Context.assistant("It is waiting on a webhook that never returned.")
        ])

      rebuilt =
        original.messages
        |> Enum.map(fn message ->
          {:ok, encoded} = Codec.encode(message)
          {:ok, decoded} = encoded |> Jason.encode!() |> Jason.decode!() |> Codec.decode()
          decoded
        end)
        |> Context.new()

      assert rebuilt == original
    end
  end

  defp round_trip(%Message{} = message) do
    with {:ok, encoded} <- Codec.encode(message) do
      encoded |> Jason.encode!() |> Jason.decode!() |> Codec.decode()
    end
  end

  defp assert_round_trips(%Message{} = message) do
    assert {:ok, decoded} = round_trip(message)
    assert decoded == message
  end

  defp assert_round_trips(%Context{} = context) do
    {:ok, message} = one_message(context)
    assert_round_trips(message)
  end

  defp one_message(%Context{messages: [message]}), do: {:ok, message}
  defp one_message(%Message{} = message), do: {:ok, message}
end
