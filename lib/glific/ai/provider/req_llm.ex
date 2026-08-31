defmodule Glific.AI.Provider.ReqLLM do
  @moduledoc """
  The `req_llm` implementation of `Glific.AI.Provider`.

  The only module that names `req_llm`, and its types stay inside: callers pass
  and receive `Glific.AI.ChatMessage` and `Glific.AI.Usage`.

  Provider failures are returned, never raised.
  """

  @behaviour Glific.AI.Provider

  require Logger

  alias Glific.AI.{ChatMessage, Models}

  @impl Glific.AI.Provider
  @spec generate([ChatMessage.t()], keyword()) ::
          {:ok, ChatMessage.t(), Glific.AI.Provider.usage()}
          | {:error, Glific.AI.Provider.failure()}
  def generate(messages, opts \\ []) do
    if Models.configured?(opts) do
      call(messages, opts)
    else
      {:error, {:not_configured, "no model is configured for Glific AI"}}
    end
  end

  @spec call([ChatMessage.t()], keyword()) ::
          {:ok, ChatMessage.t(), Glific.AI.Provider.usage()}
          | {:error, Glific.AI.Provider.failure()}
  defp call(messages, opts) do
    {model, opts} = Keyword.pop(opts, :model)

    case ReqLLM.generate_text(
           Models.spec(model: model),
           Enum.map(messages, &to_req_llm/1),
           request_opts(opts)
         ) do
      {:ok, response} ->
        {:ok, ChatMessage.assistant(ReqLLM.Response.text(response) || ""), usage(response)}

      {:error, error} ->
        # Logged here rather than at the caller: this is the only place that can
        # see the provider's own error shape.
        Logger.warning("Glific AI provider call failed: #{describe(error)}")
        {:error, {:provider_error, describe(error)}}
    end
  rescue
    exception ->
      Glific.log_exception(exception)
      {:error, {:provider_error, Exception.message(exception)}}
  end

  @spec request_opts(keyword()) :: keyword()
  defp request_opts(opts), do: Keyword.merge(Models.opts(), opts)

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

  @spec describe(term()) :: String.t()
  defp describe(%{__exception__: true} = error), do: Exception.message(error)
  defp describe(error), do: Glific.SafeLog.safe_inspect(error)
end
