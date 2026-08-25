defmodule Glific.AI.Provider.ReqLLM do
  @moduledoc """
  The `req_llm` implementation of `Glific.AI.Provider`.

  This is the **only** module in Glific that names `req_llm`. Its types do not
  escape: what goes in and comes out are `Glific.AI.Message` and
  `Glific.AI.Usage` structs. That containment is what makes the library choice
  reversible — replacing it means writing a sibling module, not migrating stored
  conversations or touching any caller.

  Every provider failure is returned, never raised. A timeout, a rate limit, a
  5xx or a model the provider rejects all arrive as `{:error, reason}` so the
  caller records a failed request instead of losing the job to an exception.
  """

  @behaviour Glific.AI.Provider

  require Logger

  alias Glific.AI.{Message, Models, Usage}

  @impl Glific.AI.Provider
  @spec generate([Message.t()], keyword()) ::
          {:ok, Message.t(), Usage.t()} | {:error, Glific.AI.Provider.failure()}
  def generate(messages, opts \\ []) do
    if Models.configured?() do
      call(messages, opts)
    else
      {:error, {:not_configured, "no model is configured for Glific AI"}}
    end
  end

  @spec call([Message.t()], keyword()) ::
          {:ok, Message.t(), Usage.t()} | {:error, Glific.AI.Provider.failure()}
  defp call(messages, opts) do
    case ReqLLM.generate_text(
           Models.spec(),
           Enum.map(messages, &to_req_llm/1),
           request_opts(opts)
         ) do
      {:ok, response} ->
        {:ok, Message.assistant(ReqLLM.Response.text(response) || ""), usage(response)}

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

  @spec to_req_llm(Message.t()) :: struct()
  defp to_req_llm(%Message{role: :system, content: content}),
    do: ReqLLM.Context.system(content || "")

  defp to_req_llm(%Message{role: :assistant, content: content}),
    do: ReqLLM.Context.assistant(content || "")

  defp to_req_llm(%Message{content: content}), do: ReqLLM.Context.user(content || "")

  @spec usage(struct()) :: Usage.t()
  defp usage(response) do
    case ReqLLM.Response.usage(response) do
      %{} = usage ->
        %Usage{
          input_tokens: Map.get(usage, :input_tokens, 0) || 0,
          output_tokens: Map.get(usage, :output_tokens, 0) || 0,
          cost: to_decimal(Map.get(usage, :total_cost))
        }

      _ ->
        %Usage{}
    end
  end

  @spec to_decimal(number() | Decimal.t() | nil) :: Decimal.t()
  defp to_decimal(nil), do: Decimal.new("0")
  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)

  @spec describe(term()) :: String.t()
  defp describe(%{__exception__: true} = error), do: Exception.message(error)
  defp describe(error), do: Glific.SafeLog.safe_inspect(error)
end
