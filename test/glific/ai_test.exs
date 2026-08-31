defmodule Glific.AITest do
  use Glific.DataCase

  alias Glific.{AI, AI.ChatMessage, AI.Models}

  # FunWithFlags keeps a global ETS cache that outlives the SQL sandbox, so each
  # test sets the flag state it depends on rather than inheriting it.
  defp enable_flag,
    do: FunWithFlags.enable(:glific_ai_enabled, for_actor: %{organization_id: 1})

  defp disable_flag,
    do: FunWithFlags.disable(:glific_ai_enabled, for_actor: %{organization_id: 1})

  defp without_model(fun) do
    original = Application.get_env(:glific, Glific.AI)
    Application.put_env(:glific, Glific.AI, Keyword.delete(original, :model))
    on_exit(fn -> Application.put_env(:glific, Glific.AI, original) end)
    fun.()
  end

  test "with the feature flag off, the request is refused before any provider call" do
    disable_flag()

    refute AI.enabled?(1)
    assert {:error, :disabled} = AI.generate(1, [ChatMessage.user("hello")])
  end

  test "with no model configured, that is reported rather than raised" do
    enable_flag()

    without_model(fn ->
      refute Models.configured?()
      assert {:error, {:not_configured, _}} = AI.generate(1, [ChatMessage.user("hello")])
    end)
  end

  test "a provider error comes back as a tuple, never as an exception" do
    enable_flag()

    assert {:error, {:provider_error, reason}} =
             AI.generate(1, [ChatMessage.user("hello")], model: "notaprovider:nope")

    assert reason =~ "unknown_provider"
  end

  test "the model comes from configuration and can be overridden per call" do
    assert Models.configured?()
    assert Models.spec() == "anthropic:claude-haiku-4-5"
    assert Models.spec(model: "anthropic:claude-opus-5") == "anthropic:claude-opus-5"
    assert Keyword.has_key?(Models.opts(), :max_tokens)
  end
end
