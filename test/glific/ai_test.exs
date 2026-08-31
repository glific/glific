defmodule Glific.AITest do
  use Glific.DataCase

  alias Glific.{AI, AI.ChatMessage}

  # FunWithFlags keeps a global ETS cache that outlives the SQL sandbox, so each
  # test sets the flag state it depends on rather than inheriting it.
  defp enable_flag,
    do: FunWithFlags.enable(:glific_ai_enabled, for_actor: %{organization_id: 1})

  defp disable_flag,
    do: FunWithFlags.disable(:glific_ai_enabled, for_actor: %{organization_id: 1})

  test "with the feature flag off, the request is refused before any provider call" do
    disable_flag()

    refute AI.enabled?(1)
    assert {:error, :disabled} = AI.generate(1, [ChatMessage.user("hello")])
  end

  test "a provider error comes back as a tuple, never as an exception" do
    enable_flag()

    assert {:error, {:provider_error, reason}} =
             AI.generate(1, [ChatMessage.user("hello")], model: "notaprovider:nope")

    assert reason =~ "unknown_provider"
  end
end
