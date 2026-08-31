defmodule Glific.AI.Provider.ReqLLM do
  @moduledoc """
  The `req_llm` implementation of `Glific.AI.Provider`.

  The only module that names `req_llm`, and its types stay inside: callers pass
  and receive `Glific.AI.ChatMessage` and a plain usage map.

  Provider failures are returned, never raised.
  """

  @behaviour Glific.AI.Provider

  require Logger

  @failure_message "The AI provider could not complete the request"

  @default_max_tokens 4_096
  @default_receive_timeout 60_000

  alias Glific.AI.{ChatMessage, Provider}

  @impl Glific.AI.Provider
  @spec generate([ChatMessage.t()], keyword()) ::
          {:ok, ChatMessage.t(), Glific.AI.Provider.usage()}
          | {:error, Glific.AI.Provider.failure()}
  def generate(messages, opts \\ []) do
    case model(opts) do
      nil -> {:error, {:not_configured, "No model is configured for Glific AI"}}
      spec -> call(spec, messages, opts)
    end
  end

  @spec call(String.t(), [ChatMessage.t()], keyword()) ::
          {:ok, ChatMessage.t(), Glific.AI.Provider.usage()}
          | {:error, Glific.AI.Provider.failure()}
  defp call(spec, messages, opts) do
    started = System.monotonic_time(:millisecond)

    case ReqLLM.generate_text(spec, Enum.map(messages, &to_req_llm/1), request_opts(opts)) do
      {:ok, response} ->
        record(spec, "succeeded", started)
        {:ok, ChatMessage.assistant(ReqLLM.Response.text(response) || ""), usage(response)}

      {:error, error} ->
        failed(spec, started, Glific.SafeLog.safe_inspect(error))
    end
  rescue
    exception ->
      Glific.log_exception(exception)
      {:error, {:provider_error, @failure_message}}
  catch
    :exit, reason ->
      failed(spec, System.monotonic_time(:millisecond), Glific.SafeLog.safe_inspect(reason))
  end

  @spec failed(String.t(), integer(), String.t()) :: {:error, Provider.failure()}
  defp failed(spec, started, detail) do
    record(spec, "failed", started)
    Glific.log_error("Glific AI call failed on #{spec}: #{detail}")
    {:error, {:provider_error, @failure_message}}
  end

  @spec record(String.t(), String.t(), integer()) :: :ok
  defp record(spec, outcome, started) do
    tags = %{outcome: outcome, model: spec}
    Appsignal.increment_counter("glific_ai_call_count", 1, tags)

    Appsignal.add_distribution_value(
      "glific_ai_call_latency",
      System.monotonic_time(:millisecond) - started,
      tags
    )
  end

  @spec request_opts(keyword()) :: keyword()
  # max_tokens and receive_timeout are req_llm's own option names, so the mapping
  # from our config stays here rather than in the behaviour.
  @spec request_opts(keyword()) :: keyword()
  defp request_opts(opts) do
    [
      max_tokens: config()[:max_tokens] || @default_max_tokens,
      receive_timeout: config()[:receive_timeout] || @default_receive_timeout
    ]
    |> Keyword.merge(Keyword.delete(opts, :model))
  end

  @spec config() :: keyword()
  defp config, do: Application.get_env(:glific, Glific.AI, [])

  @spec model(keyword()) :: String.t() | nil
  defp model(opts) do
    case opts[:model] do
      override when is_binary(override) and override != "" -> override
      _ -> config()[:model]
    end
  end

  @spec to_req_llm(ChatMessage.t()) :: struct()
  defp to_req_llm(%ChatMessage{role: :system, content: content}),
    do: ReqLLM.Context.system(content || "")

  defp to_req_llm(%ChatMessage{role: :assistant, content: content}),
    do: ReqLLM.Context.assistant(content || "")

  defp to_req_llm(%ChatMessage{content: content}), do: ReqLLM.Context.user(content || "")

  @spec usage(struct()) :: Glific.AI.Provider.usage()
  defp usage(response) do
    usage = ReqLLM.Response.usage(response) || %{}

    %{
      input_tokens: Map.get(usage, :input_tokens) || 0,
      output_tokens: Map.get(usage, :output_tokens) || 0,
      cost: Map.get(usage, :total_cost) || 0
    }
  end
end
