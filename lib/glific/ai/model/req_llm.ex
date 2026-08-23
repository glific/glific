defmodule Glific.AI.Model.ReqLLM do
  @moduledoc """
  The real `Glific.AI.Model` adapter: wraps `ReqLLM.Generation.generate_text/3` and
  `generate_object/4`.

  `opts` must carry `:model` (a `req_llm` model spec string, e.g. `"anthropic:claude-sonnet-5"`,
  as returned by a skill's `model/0`) and `:api_key` (from `Glific.AI.Credentials.fetch/2`).
  Every other key is forwarded to `ReqLLM.Generation` as-is, with three exceptions this module
  enforces regardless of what the caller passed:

    * `temperature: 0` fails `ReqLLM`'s option validation ("expected float, got: 0") — an
      integer temperature is coerced to a float before the call ever reaches it.
    * `receive_timeout` is clamped below 45s. One agent step runs inside an Oban job under a
      45s wall clock (`shutdown_grace_period` is 60s, `config/config.exs`), so a model call that
      outlives the step budget defeats the job-per-step design regardless of what the caller
      asked for.
    * When the resolved model's provider is `:anthropic`, prompt caching is turned on:
      `anthropic_cache_messages: -2` caches everything up to the second-to-last message, so tool
      definitions, the system prompt, and prior turns stay warm and only the newest input goes
      in uncached. `opts[:cache_ttl]` (a skill's `cache_ttl/0`) becomes
      `anthropic_prompt_cache_ttl` when present. This is never sent to a non-Anthropic provider,
      which would reject the unknown option.
  """

  @behaviour Glific.AI.Model

  alias Glific.AI.Codec
  alias Glific.AI.Model.Result
  alias Glific.AI.Skill
  alias Glific.SafeLog
  alias ReqLLM.Context
  alias ReqLLM.Usage

  @receive_timeout_ms 40_000
  @max_receive_timeout_ms 44_000

  @impl true
  @spec chat(Context.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def chat(%Context{} = context, opts) do
    with {:ok, model_spec, call_opts} <- request_opts(opts),
         {:ok, response} <- ReqLLM.Generation.generate_text(model_spec, context, call_opts),
         {:ok, result} <- to_result(response) do
      {:ok, result}
    else
      {:error, reason} -> call_failed("chat", reason)
    end
  end

  @impl true
  @spec object(Context.t(), Skill.output_schema(), keyword()) :: {:ok, map()} | {:error, term()}
  def object(%Context{} = context, schema, opts) do
    with {:ok, model_spec, call_opts} <- request_opts(opts),
         {:ok, response} <-
           ReqLLM.Generation.generate_object(model_spec, context, schema, call_opts),
         %{} = object <- ReqLLM.Response.object(response) do
      {:ok, object}
    else
      nil -> call_failed("object", :no_object_returned)
      {:error, reason} -> call_failed("object", reason)
    end
  end

  @doc false
  @spec request_opts(keyword()) :: {:ok, String.t(), keyword()} | {:error, :missing_model}
  def request_opts(opts) do
    case Keyword.fetch(opts, :model) do
      {:ok, model_spec} when is_binary(model_spec) ->
        call_opts =
          opts
          |> Keyword.drop([:model, :cache_ttl])
          |> normalize_temperature()
          |> put_receive_timeout()
          |> maybe_put_prompt_cache(model_spec, Keyword.get(opts, :cache_ttl))

        {:ok, model_spec, call_opts}

      _missing ->
        {:error, :missing_model}
    end
  end

  @spec normalize_temperature(keyword()) :: keyword()
  defp normalize_temperature(opts) do
    case Keyword.fetch(opts, :temperature) do
      {:ok, temperature} when is_integer(temperature) ->
        Keyword.put(opts, :temperature, temperature * 1.0)

      _unchanged ->
        opts
    end
  end

  @spec put_receive_timeout(keyword()) :: keyword()
  defp put_receive_timeout(opts) do
    requested = Keyword.get(opts, :receive_timeout, @receive_timeout_ms)
    Keyword.put(opts, :receive_timeout, min(requested, @max_receive_timeout_ms))
  end

  @spec maybe_put_prompt_cache(keyword(), String.t(), String.t() | nil) :: keyword()
  defp maybe_put_prompt_cache(call_opts, model_spec, cache_ttl) do
    if anthropic?(model_spec) do
      provider_options =
        [anthropic_prompt_cache: true, anthropic_cache_messages: -2]
        |> maybe_put_cache_ttl(cache_ttl)

      Keyword.update(
        call_opts,
        :provider_options,
        provider_options,
        &Keyword.merge(&1, provider_options)
      )
    else
      call_opts
    end
  end

  @spec anthropic?(String.t()) :: boolean()
  defp anthropic?(model_spec) do
    case ReqLLM.model(model_spec) do
      {:ok, %{provider: :anthropic}} -> true
      _not_anthropic -> false
    end
  end

  @spec maybe_put_cache_ttl(keyword(), String.t() | nil) :: keyword()
  defp maybe_put_cache_ttl(provider_options, nil), do: provider_options

  defp maybe_put_cache_ttl(provider_options, cache_ttl),
    do: Keyword.put(provider_options, :anthropic_prompt_cache_ttl, cache_ttl)

  @doc false
  @spec to_result(ReqLLM.Response.t()) :: {:ok, Result.t()} | {:error, :no_message_returned}
  def to_result(%ReqLLM.Response{message: nil}), do: {:error, :no_message_returned}

  def to_result(%ReqLLM.Response{} = response) do
    {:ok,
     %Result{
       message: Codec.normalize(response.message),
       tool_calls: ReqLLM.Response.tool_calls(response),
       finish_reason: response.finish_reason,
       usage: usage(response.usage),
       context: response.context
     }}
  end

  @spec usage(map() | nil) :: Result.usage()
  defp usage(nil), do: Result.zero_usage()

  defp usage(usage) do
    normalized = Usage.normalize(usage)

    %{
      prompt: normalized[:input_tokens] || 0,
      completion: normalized[:output_tokens] || 0,
      cached: normalized[:cached_tokens] || 0,
      cache_creation: normalized[:cache_creation_tokens] || 0
    }
  end

  @spec call_failed(String.t(), term()) :: {:error, String.t()}
  defp call_failed(operation, reason) do
    Glific.log_error(
      "Glific.AI.Model.ReqLLM.#{operation} failed: #{SafeLog.safe_inspect(reason)}"
    )
  end
end
