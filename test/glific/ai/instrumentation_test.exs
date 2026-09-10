defmodule Glific.AI.InstrumentationTest.StubProvider do
  @moduledoc false
  @behaviour Glific.AI.Provider

  @impl Glific.AI.Provider
  def generate(_messages, opts), do: Keyword.fetch!(opts, :reply)

  @impl Glific.AI.Provider
  def model(opts), do: opts[:model]
end

defmodule Glific.AI.InstrumentationTest do
  use Glific.DataCase

  alias Glific.AI.{ChatMessage, Instrumentation}
  alias Glific.AI.InstrumentationTest.StubProvider

  defp around(opts) do
    Instrumentation.around(StubProvider, opts, fn ->
      StubProvider.generate([ChatMessage.user("hi")], opts)
    end)
  end

  test "the provider's result is returned untouched" do
    reply =
      {:ok, ChatMessage.assistant("an answer"), %{input_tokens: 1, output_tokens: 2, cost: 0}}

    assert ^reply = around(model: "anthropic:claude-haiku-4-5", reply: reply)
  end

  test "a failure is recorded and still returned to the caller" do
    reply = {:error, {:provider_error, "The AI provider could not complete the request"}}

    assert ^reply = around(model: "anthropic:claude-haiku-4-5", reply: reply)
  end

  test "an unconfigured model is tagged rather than crashing the call" do
    reply = {:error, {:not_configured, "No model is configured for Glific AI"}}

    assert ^reply = around(reply: reply)
  end

  test "every caller reaches the provider through the instrumented path" do
    for module <- [Glific.AI.Agent, Glific.AI.Router] do
      source = module.module_info(:compile)[:source] |> to_string() |> File.read!()

      refute source =~ "Provider.impl().generate",
             "#{inspect(module)} calls the provider directly, so its calls are not measured"

      assert source =~ "AI.generate("
    end
  end
end
