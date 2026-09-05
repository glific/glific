defmodule Glific.FakeProvider do
  @moduledoc """
  A real HTTP server that answers like Anthropic, so tests exercise the actual
  `Glific.AI.Provider.ReqLLM` adapter — Finch, Req and req_llm's decoding
  included — rather than substituting a provider of their own.

  `script/1` stages the replies a run should receive, in order. Use `answer/1`
  for a final answer and `tool_use/2` for a turn where the model asks for a tool.
  """

  import Plug.Conn

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, _opts) do
    {:ok, body, conn} = read_body(conn)

    reply =
      case Agent.get_and_update(__MODULE__, &pop/1) do
        nil -> Agent.get(__MODULE__, &Map.get(&1, :always)) || answer("done")
        staged -> staged
      end

    Agent.update(__MODULE__, fn state ->
      Map.update(state, :seen, [body], &(&1 ++ [body]))
    end)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(reply))
  end

  @doc "Starts the server and returns the config a test should install."
  @spec start() :: keyword()
  def start do
    {:ok, _} = Agent.start_link(fn -> %{replies: [], seen: []} end, name: __MODULE__)
    {:ok, _} = Plug.Cowboy.http(__MODULE__, [], port: 0, ref: __MODULE__.HTTP)

    [
      base_url: "http://127.0.0.1:#{:ranch.get_port(__MODULE__.HTTP)}/v1",
      api_key: "sk-ant-test"
    ]
  end

  @doc "Stops the server."
  @spec stop() :: :ok
  def stop, do: Plug.Cowboy.shutdown(__MODULE__.HTTP)

  @doc "Stages the replies this run should receive, in order."
  @spec script([map()]) :: :ok
  def script(replies), do: Agent.update(__MODULE__, &Map.put(&1, :replies, replies))

  @doc "Stages one reply to return for every call, for testing a run that will not stop."
  @spec always(map()) :: :ok
  def always(reply), do: Agent.update(__MODULE__, &Map.put(&1, :always, reply))

  @doc "The raw request bodies the provider received, oldest first."
  @spec seen() :: [String.t()]
  def seen, do: Agent.get(__MODULE__, &Map.get(&1, :seen, []))

  @doc "A final answer."
  @spec answer(String.t(), keyword()) :: map()
  def answer(text, opts \\ []) do
    %{
      "id" => "msg_1",
      "type" => "message",
      "role" => "assistant",
      "model" => "claude-haiku-4-5",
      "content" => [%{"type" => "text", "text" => text}],
      "stop_reason" => "end_turn",
      "usage" => usage(opts)
    }
  end

  @doc "A turn where the model asks for several tools at once."
  @spec tool_uses([{String.t(), map()}], keyword()) :: map()
  def tool_uses(calls, opts \\ []) do
    content =
      calls
      |> Enum.with_index(1)
      |> Enum.map(fn {{name, input}, index} ->
        %{"type" => "tool_use", "id" => "toolu_#{index}", "name" => name, "input" => input}
      end)

    %{
      "id" => "msg_1",
      "type" => "message",
      "role" => "assistant",
      "model" => "claude-haiku-4-5",
      "content" => content,
      "stop_reason" => "tool_use",
      "usage" => usage(opts)
    }
  end

  @doc "A turn where the model asks for one tool."
  @spec tool_use(String.t(), map(), keyword()) :: map()
  def tool_use(name, input \\ %{}, opts \\ []) do
    %{
      "id" => "msg_1",
      "type" => "message",
      "role" => "assistant",
      "model" => "claude-haiku-4-5",
      "content" => [
        %{
          "type" => "tool_use",
          "id" => Keyword.get(opts, :id, "toolu_1"),
          "name" => name,
          "input" => input
        }
      ],
      "stop_reason" => "tool_use",
      "usage" => usage(opts)
    }
  end

  defp usage(opts) do
    %{
      "input_tokens" => Keyword.get(opts, :input_tokens, 10),
      "output_tokens" => Keyword.get(opts, :output_tokens, 5)
    }
  end

  defp pop(%{replies: []} = state), do: {nil, state}
  defp pop(%{replies: [head | rest]} = state), do: {head, %{state | replies: rest}}
end
