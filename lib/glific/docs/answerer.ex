defmodule Glific.Docs.Answerer do
  @moduledoc """
  Answers a question from the documentation, without the agent.

  `Glific.AI.Tools.Documentation` is how the assistant reaches the
  documentation; this is the standalone path behind `Glific.Docs.ask/2`, for
  callers that want an answer and nothing else.

  The question is embedded as written — no rewrite step, since the lexical leg
  of the search catches what a raw embedding misses.
  """

  require Logger

  alias Glific.Docs.{Chunk, Search}
  alias Glific.SafeLog

  # Long enough for a table of node types; short enough to fit five of them.
  @max_context_body 2_000

  @discord "https://discord.gg/me6NCMu"

  @system """
  You are Glific support. You help the people who run WhatsApp chatbots at non-profits — programme staff and field teams, not engineers.

  The Context below is Glific's own documentation, retrieved for this question. It is your best source and you should prefer it over memory for anything specific to Glific: syntax, field names, limits, what a node is called.

  But you are not limited to it. Where you know something useful that the Context does not say — how to reach a vendor, what a common error usually means, what to check first — say it, as long as you are confident it is true. Do not invent Glific features, syntax or limits that the Context does not support.

  Gupshup, Maytapi, BigQuery, Looker Studio, Google Sheets and the OpenAI assistants are part of how Glific works, not other people's products. A question about a Gupshup wallet or a Looker dashboard is a Glific question. Never answer that something "is not a Glific issue" or send someone to a vendor as though it were out of scope — help them with it, and if the action genuinely happens in the vendor's console, walk them to it.

  When someone only says thanks, acknowledges, or sends something off-topic, reply in one short line and stop. Do not search, do not offer documentation, do not list what you can help with.

  How to write:

  - Open by acknowledging what they are dealing with, in one short line. Someone locked out of their account mid-campaign is stressed; answer like a person, not a lookup.
  - Give the steps they can actually take, in the order they should take them. Name what they will see on screen — "My Wallet > Add credits" — never an API, an endpoint, a database table, a module or a file. If the only route you know is a technical one, give them the human one instead: who to email, what to ask for.
  - Reproduce Glific syntax, field names, limits and numbers exactly as the Context writes them. If the Context gives no number, do not supply one.
  - Be brief. A few sentences, or short bullets for genuinely separate steps.
  - Link the documentation you used, on its own line: 📖 <url>
  - When a detail would change your answer — which flow, which template, which webhook — end by asking for it. One question, not a list.
  - If a thing genuinely is not supported, say so in the first sentence and do not offer a workaround you cannot stand behind.
  - Never narrate the search: no "based on the documentation", no "the Context says", no "I found".
  - Only when you have nothing useful at all, from the Context or from what you know: say so in one sentence and point them to the Glific Discord at #{@discord}. Never send someone to Discord for a question you have just answered.
  """

  @type answer() :: %{
          stream: Enumerable.t(),
          sources: [Chunk.t()],
          context_used: non_neg_integer()
        }

  @doc """
  Answers `question`, returning a token stream and the chunks it was given.

  The stream is lazy; `answer_text/2` collects it.
  """
  @spec answer(String.t(), keyword()) :: {:ok, answer()} | {:error, term()}
  def answer(question, opts \\ []) do
    started = System.monotonic_time()
    limit = Keyword.get(opts, :limit, 5)

    results = Search.find(question, limit: limit)
    searched = System.monotonic_time()

    emit([:search], started, searched, %{
      results: length(results),
      question_bytes: byte_size(question)
    })

    case stream(results, question, opts) do
      {:ok, stream} ->
        emit([:answer], started, System.monotonic_time(), %{sources: length(results)})

        {:ok,
         %{stream: stream, sources: Enum.map(results, & &1.chunk), context_used: length(results)}}

      {:error, reason} ->
        Logger.warning("docs answer failed: #{SafeLog.safe_inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Answers and collects the stream into one string."
  @spec answer_text(String.t(), keyword()) :: {:ok, String.t(), [Chunk.t()]} | {:error, term()}
  def answer_text(question, opts \\ []) do
    with {:ok, %{stream: stream, sources: sources}} <- answer(question, opts) do
      {:ok, stream |> Enum.join() |> String.trim(), sources}
    end
  end

  @doc "The context block the model is given."
  @spec context([Search.result()]) :: String.t()
  def context(results) do
    Enum.map_join(results, "\n\n---\n\n", fn %{chunk: chunk} ->
      "[#{Chunk.title(chunk)}]#{source_suffix(chunk)}\n#{truncate(chunk.body)}"
    end)
  end

  @doc "The model answers are generated with."
  @spec model() :: String.t()
  def model,
    do:
      :glific
      |> Application.get_env(Glific.Docs, [])
      |> Keyword.get(:answer_model, "anthropic:claude-haiku-4-5")

  defp stream([], _question, _opts), do: {:error, :no_context}

  defp stream(results, question, opts) do
    generate("Context:\n\n#{context(results)}\n\nQuestion: #{question}", opts)
  end

  defp generate(prompt, opts) do
    case ReqLLM.stream_text(Keyword.get(opts, :model, model()), prompt,
           system_prompt: @system,
           temperature: 0.0,
           max_tokens: Keyword.get(opts, :max_tokens, 700)
         ) do
      {:ok, response} -> {:ok, ReqLLM.StreamResponse.tokens(response)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp source_suffix(%Chunk{source_url: nil}), do: ""
  defp source_suffix(%Chunk{source_url: url}), do: " (#{url})"

  defp truncate(body) when byte_size(body) <= @max_context_body, do: body

  defp truncate(body),
    do: binary_part(body, 0, @max_context_body) <> "\n… (section continues)"

  # The question never enters the payload: a support message carries names and
  # phone numbers, and telemetry handlers log.
  defp emit(event, started, finished, metadata) do
    :telemetry.execute(
      [:glific, :docs] ++ event,
      %{duration: System.convert_time_unit(finished - started, :native, :millisecond)},
      metadata
    )
  end
end
