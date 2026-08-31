defmodule Glific.AITest do
  use Glific.DataCase

  alias Glific.{AI, AI.ChatMessage, AI.Provider.ReqLLM}

  # A real HTTP server, so these tests exercise Finch, Req and req_llm's decoding
  # rather than a stub of our own. Each test says what the provider should return.
  defmodule FakeAnthropic do
    @moduledoc false
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, _opts) do
      {status, body} = Agent.get(__MODULE__, & &1)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(body))
    end

    def respond(status, body), do: Agent.update(__MODULE__, fn _ -> {status, body} end)

    def answer(text, usage \\ %{"input_tokens" => 11, "output_tokens" => 3}) do
      %{
        "id" => "msg_1",
        "type" => "message",
        "role" => "assistant",
        "model" => "claude-haiku-4-5",
        "content" => [%{"type" => "text", "text" => text}],
        "stop_reason" => "end_turn",
        "usage" => usage
      }
    end
  end

  setup do
    {:ok, _} = Agent.start_link(fn -> {200, FakeAnthropic.answer("ok")} end, name: FakeAnthropic)
    {:ok, _} = Plug.Cowboy.http(FakeAnthropic, [], port: 0, ref: FakeAnthropic.HTTP)
    port = :ranch.get_port(FakeAnthropic.HTTP)
    on_exit(fn -> Plug.Cowboy.shutdown(FakeAnthropic.HTTP) end)

    # FunWithFlags state outlives the SQL sandbox, and it cannot be restored in
    # on_exit because the sandbox connection is already gone by then. Every test
    # that depends on the flag therefore sets it, here or in its own body.
    FunWithFlags.enable(:glific_ai_enabled, for_actor: %{organization_id: 1})

    %{opts: [base_url: "http://127.0.0.1:#{port}/v1", api_key: "sk-ant-test"]}
  end

  defp ask(opts), do: ReqLLM.generate([ChatMessage.user("hello")], opts)

  test "a successful reply is decoded into a ChatMessage with its usage", %{opts: opts} do
    FakeAnthropic.respond(200, FakeAnthropic.answer("An HSM is a template."))

    assert {:ok, %ChatMessage{role: :assistant, content: "An HSM is a template."}, usage} =
             ask(opts)

    assert usage == %{input_tokens: 11, output_tokens: 3, cost: usage.cost}
    assert is_number(usage.cost)
  end

  test "usage missing from the response does not crash", %{opts: opts} do
    FakeAnthropic.respond(200, FakeAnthropic.answer("hi", %{}))

    assert {:ok, _, %{input_tokens: 0, output_tokens: 0}} = ask(opts)
  end

  test "every provider failure returns the same generic reason, with no request detail",
       %{opts: opts} do
    for status <- [401, 403, 429, 500, 503] do
      FakeAnthropic.respond(status, %{"error" => %{"message" => "provider said #{status}"}})

      assert {:error, {:provider_error, reason}} = ask(opts)
      refute reason =~ "sk-ant"
      refute reason =~ "api_key"
      refute reason =~ to_string(status)
    end
  end

  test "with no model configured, that is distinguishable from a provider failure" do
    original = Application.get_env(:glific, Glific.AI)
    Application.put_env(:glific, Glific.AI, Keyword.delete(original, :model))
    on_exit(fn -> Application.put_env(:glific, Glific.AI, original) end)

    assert {:error, {:not_configured, _}} = ReqLLM.generate([ChatMessage.user("hi")])
  end

  test "with the feature flag off, the request is refused before any provider call" do
    FunWithFlags.disable(:glific_ai_enabled, for_actor: %{organization_id: 1})

    refute AI.enabled?(1)
    assert {:error, :disabled} = AI.generate(1, [ChatMessage.user("hello")])
  end
end
