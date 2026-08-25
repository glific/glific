defmodule Glific.AITest do
  use Glific.DataCase

  alias Glific.{AI, AI.Message, AI.Models, AI.Usage}

  defmodule RecordingProvider do
    @moduledoc false
    @behaviour Glific.AI.Provider

    @impl Glific.AI.Provider
    def generate(messages, _opts) do
      send(self(), {:provider_called, messages})

      {:ok, Message.assistant("a reply"),
       %Usage{input_tokens: 12, output_tokens: 4, cost: Decimal.new("0.0006")}}
    end
  end

  defmodule FailingProvider do
    @moduledoc false
    @behaviour Glific.AI.Provider

    @impl Glific.AI.Provider
    def generate(_messages, _opts), do: {:error, {:provider_error, "429 rate limited"}}
  end

  defp configure(provider) do
    original = Application.get_env(:glific, Glific.AI)
    Application.put_env(:glific, Glific.AI, Keyword.put(original, :provider, provider))
    on_exit(fn -> Application.put_env(:glific, Glific.AI, original) end)
  end

  # FunWithFlags keeps a global ETS cache, so flag state outlives the SQL sandbox and
  # leaks between tests. Each test therefore sets the state it depends on explicitly.
  defp enable_flag,
    do: FunWithFlags.enable(:glific_ai_enabled, for_actor: %{organization_id: 1})

  defp disable_flag,
    do: FunWithFlags.disable(:glific_ai_enabled, for_actor: %{organization_id: 1})

  test "with the feature flag off, no provider call is made" do
    configure(RecordingProvider)
    disable_flag()

    refute AI.enabled?(1)
    assert {:error, :disabled} = AI.generate(1, [Message.user("hello")])
    refute_received {:provider_called, _}
  end

  test "with the flag on, the call goes through and usage comes back" do
    configure(RecordingProvider)
    enable_flag()

    assert AI.enabled?(1)

    assert {:ok, %Message{role: :assistant, content: "a reply"}, %Usage{} = usage} =
             AI.generate(1, [Message.user("hello")])

    assert usage.input_tokens == 12
    assert usage.output_tokens == 4
    assert Decimal.equal?(usage.cost, Decimal.new("0.0006"))

    assert_received {:provider_called, [%Message{role: :user, content: "hello"}]}
  end

  test "a provider failure is returned, not raised" do
    configure(FailingProvider)
    enable_flag()

    assert {:error, {:provider_error, "429 rate limited"}} =
             AI.generate(1, [Message.user("hello")])
  end

  test "the model spec comes from configuration, and a missing one is reported rather than raised" do
    assert Models.configured?()
    assert is_binary(Models.spec())
    assert Keyword.has_key?(Models.opts(), :max_tokens)

    original = Application.get_env(:glific, Glific.AI)
    Application.put_env(:glific, Glific.AI, Keyword.delete(original, :model))
    on_exit(fn -> Application.put_env(:glific, Glific.AI, original) end)

    refute Models.configured?()
    enable_flag()

    assert {:error, {:not_configured, _}} = AI.generate(1, [Message.user("hello")])
  end

  test "usages accumulate, so a request can total the calls it made" do
    total =
      Usage.add(
        %Usage{input_tokens: 10, output_tokens: 5, cost: Decimal.new("0.001")},
        %Usage{input_tokens: 3, output_tokens: 2, cost: Decimal.new("0.002")}
      )

    assert total.input_tokens == 13
    assert total.output_tokens == 7
    assert Decimal.equal?(total.cost, Decimal.new("0.003"))
  end
end
