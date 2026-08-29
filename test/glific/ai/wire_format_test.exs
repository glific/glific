defmodule Glific.AI.WireFormatTest do
  @moduledoc """
  Asserts what actually goes on the wire to the provider.

  The stubbed providers used elsewhere never exercise the conversion, so a turn
  that carried tool calls could be silently dropped there and only fail against
  a real provider. These tests encode a conversation the way Anthropic will
  receive it and check that it is coherent.
  """

  use ExUnit.Case, async: true

  alias Glific.AI.{ChatMessage, Tools}
  alias Glific.AI.Provider.ReqLLM, as: Adapter

  defp encode(messages) do
    {:ok, model} = Elixir.ReqLLM.model("anthropic:claude-opus-5")

    {:ok, context} =
      messages
      |> Adapter.to_provider_chat_messages()
      |> Elixir.ReqLLM.Context.normalize()

    Elixir.ReqLLM.Providers.Anthropic.Context.encode_request(context, model)
  end

  test "an assistant turn that asked for tools keeps those calls on the wire" do
    call = %{id: "toolu_1", name: "list_flows", args: %{"name" => "Reg"}}

    encoded =
      encode([
        ChatMessage.system("you are a helper"),
        ChatMessage.user("what flows do I have?"),
        ChatMessage.assistant(nil, [call]),
        ChatMessage.tool_result("toolu_1", "list_flows", ~s({"flows":[]}))
      ])

    blocks = encoded[:messages] |> Enum.flat_map(&List.wrap(&1[:content] || &1["content"]))

    tool_use = Enum.find(blocks, &(block_type(&1) == "tool_use"))
    tool_result = Enum.find(blocks, &(block_type(&1) == "tool_result"))

    assert tool_use, "the assistant's tool call must reach the provider"
    assert get(tool_use, :name) == "list_flows"
    assert get(tool_use, :input) == %{"name" => "Reg"}

    assert tool_result, "the tool's output must reach the provider"

    # The pairing is the point: a tool_result whose id was never announced in a
    # preceding tool_use is rejected by the provider.
    assert get(tool_use, :id) == get(tool_result, :tool_use_id)
  end

  test "a plain assistant turn is unaffected" do
    encoded = encode([ChatMessage.user("hi"), ChatMessage.assistant("hello")])
    roles = Enum.map(encoded[:messages], &(&1[:role] || &1["role"]))
    assert roles == ["user", "assistant"]
  end

  test "every tool converts to something the provider will accept" do
    for tool <- Tools.all() do
      assert %{name: name, description: description} =
               Elixir.ReqLLM.tool(
                 name: tool.name(),
                 description: tool.description(),
                 parameter_schema: tool.parameters(),
                 callback: fn _ -> {:ok, nil} end
               )

      assert name == tool.name()
      assert is_binary(description)
    end
  end

  defp block_type(block), do: get(block, :type)

  defp get(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp get(_, _), do: nil
end
