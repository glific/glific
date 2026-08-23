defmodule Glific.AI.Telemetry.Handlers do
  @moduledoc """
  Forwards `req_llm`'s native `:telemetry` events to AppSignal as custom metrics, mirroring how
  the rest of Glific reports Oban/Tesla/Repo telemetry (see `Glific.Appsignal`).

  Only metric names and tags leave this module — provider, model, finish reason, and the
  caller context from `Glific.AI.Telemetry.Context` (organization id, skill). No prompt,
  completion, or tool payload is ever read here; `req_llm`'s request/exception/token-usage
  metadata carries those only when a call opts into `telemetry: [payloads: :raw]`, and this
  module never reads the payload-carrying keys even when present.

  A handler must never raise — an AppSignal hiccup must never take down a model call. Every
  event is dispatched through a `rescue` so a crash here is logged via `Glific.log_exception/1`
  and swallowed instead of propagating back into `req_llm`'s telemetry span.
  """

  alias Glific.AI.Telemetry.Context

  @handler_id "glific-ai-appsignal"

  @doc "Attaches the AppSignal-forwarding handlers for the `req_llm` events this module covers."
  @spec attach() :: :ok
  def attach do
    case :telemetry.attach_many(@handler_id, handled_events(), &__MODULE__.handle_event/4, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  # `[:req_llm, :request, :retry]` is not in `stable_events/0` — its metadata is still
  # experimental — but a rising retry rate is the earliest signal of provider trouble, so it is
  # added explicitly on top of the stable core rather than waiting for it to stabilise.
  @spec handled_events() :: [[atom()]]
  defp handled_events do
    (ReqLLM.Telemetry.stable_events() -- [[:req_llm, :request, :start]]) ++
      [[:req_llm, :request, :retry]]
  end

  @doc false
  @spec handle_event(list(atom()), map(), map(), term()) :: :ok
  def handle_event(event, measurements, metadata, config) do
    do_handle_event(event, measurements, metadata, config)
  rescue
    exception ->
      Glific.log_exception(exception)
      :ok
  end

  @spec do_handle_event(list(atom()), map(), map(), term()) :: :ok
  defp do_handle_event([:req_llm, :request, :stop], measurements, metadata, _config) do
    tags = base_tags(metadata)

    measurements
    |> Map.get(:duration)
    |> native_to_ms()
    |> record_duration(tags)

    record_token_metrics(Map.get(metadata, :usage), nil, tags)

    :ok
  end

  defp do_handle_event([:req_llm, :request, :exception], measurements, metadata, _config) do
    tags = base_tags(metadata)

    Appsignal.increment_counter("ai_request_exception_count", 1, tags)

    measurements
    |> Map.get(:duration)
    |> native_to_ms()
    |> record_duration(tags)

    :ok
  end

  defp do_handle_event([:req_llm, :token_usage], measurements, metadata, _config) do
    tags = base_tags(metadata)
    record_token_metrics(Map.get(measurements, :tokens), Map.get(measurements, :cost), tags)
    :ok
  end

  defp do_handle_event([:req_llm, :request, :retry], _measurements, metadata, _config) do
    Appsignal.increment_counter("ai_request_retry_count", 1, base_tags(metadata))
    :ok
  end

  defp do_handle_event(_event, _measurements, _metadata, _config), do: :ok

  @spec base_tags(map()) :: map()
  defp base_tags(metadata) when is_map(metadata) do
    context = Context.get()

    %{
      provider: tag_value(Map.get(metadata, :provider)),
      model: tag_value(model_id(Map.get(metadata, :model))),
      finish_reason: tag_value(Map.get(metadata, :finish_reason)),
      organization_id: tag_value(Map.get(context, :organization_id)),
      skill: tag_value(Map.get(context, :skill))
    }
  end

  defp base_tags(_metadata), do: base_tags(%{})

  @spec model_id(term()) :: term()
  defp model_id(%{id: id}), do: id
  defp model_id(_model), do: nil

  @spec tag_value(term()) :: String.t()
  defp tag_value(nil), do: "unknown"
  defp tag_value(value) when is_atom(value), do: Atom.to_string(value)
  defp tag_value(value) when is_binary(value), do: value
  defp tag_value(value), do: to_string(value)

  @spec native_to_ms(term()) :: number() | nil
  defp native_to_ms(duration) when is_integer(duration),
    do: System.convert_time_unit(duration, :native, :millisecond)

  defp native_to_ms(_duration), do: nil

  @spec record_duration(number() | nil, map()) :: :ok
  defp record_duration(nil, _tags), do: :ok

  defp record_duration(duration_ms, tags) do
    Appsignal.add_distribution_value("ai_request_duration", duration_ms, tags)
    :ok
  end

  @spec record_token_metrics(term(), term(), map()) :: :ok
  defp record_token_metrics(tokens, cost, tags) when is_map(tokens) do
    record_token_value(token_value(tokens, [:input_tokens, :input]), "input", tags)
    record_token_value(token_value(tokens, [:output_tokens, :output]), "output", tags)
    record_token_value(token_value(tokens, [:total_tokens, :total]), "total", tags)
    record_cost(cost, tags)
    :ok
  end

  defp record_token_metrics(_tokens, cost, tags) do
    record_cost(cost, tags)
    :ok
  end

  @spec token_value(map(), [atom()]) :: term()
  defp token_value(tokens, keys), do: Enum.find_value(keys, fn key -> Map.get(tokens, key) end)

  @spec record_token_value(term(), String.t(), map()) :: :ok
  defp record_token_value(value, _token_type, _tags) when not is_number(value), do: :ok

  defp record_token_value(value, token_type, tags) do
    Appsignal.add_distribution_value(
      "ai_token_usage",
      value,
      Map.put(tags, :token_type, token_type)
    )

    :ok
  end

  @spec record_cost(term(), map()) :: :ok
  defp record_cost(cost, _tags) when not is_number(cost), do: :ok

  defp record_cost(cost, tags) do
    Appsignal.add_distribution_value("ai_request_cost", cost, tags)
    :ok
  end
end
