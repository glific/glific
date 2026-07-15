defmodule Glific.Flows.Webhooks.Dispatcher do
  @moduledoc """
  Single entry point for invoking a registered flow webhook by name: looks it up in the
  `Registry`, builds a context, and runs `call/2` inside `Instrumentation.around/3`. Only nodes
  registered in the `Registry` route here (org-specific client modules go via
  `Glific.Clients.webhook/2`).
  """

  alias Glific.Flows.Webhooks.{Instrumentation, Registry, ResultTranslator}

  @doc "Dispatch a registered webhook by name with the parsed fields (+ optional headers)."
  @spec dispatch(String.t(), map(), keyword() | list()) :: any()
  def dispatch(name, fields, headers \\ []) when is_binary(name) and is_map(fields) do
    module = Registry.lookup!(name)
    ctx = build_context(fields, headers)

    # Translation runs after instrumentation so around/3 sees the raw typed result; the flow
    # engine only ever sees the translated legacy shape.
    module
    |> Instrumentation.around(ctx, fn -> module.call(fields, ctx) end)
    |> ResultTranslator.to_legacy_structure(module)
  end

  @doc """
  Dispatch a registered webhook's callback phase (the async Kaapi POST-back), instrumented like
  the call phase. Returns the (possibly post-processed) response the flow resumes on. An
  unregistered/absent name passes the response through unchanged.
  """
  @spec callback(String.t() | nil, map(), map()) :: map()
  def callback(name, result, response) when is_map(result) and is_map(response) do
    case Registry.lookup(name) do
      nil ->
        Instrumentation.around_callback(nil, result, response, fn -> response end)

      module ->
        ctx = callback_ctx(response)

        Instrumentation.around_callback(module, result, response, fn ->
          module.callback(result, response, ctx)
        end)
    end
  end

  # Mirrors build_context so the callback and dispatch phases see the same ctx shape.
  @spec callback_ctx(map()) :: map()
  defp callback_ctx(response) do
    %{
      organization_id: response["organization_id"],
      flow_id: response["flow_id"],
      contact_id: response["contact_id"],
      webhook_log_id: response["webhook_log_id"]
    }
  end

  # Carries the flow-context ids so a failure reported before the callback (dispatch failure /
  # crash) still tags contact/flow/webhook_log.
  @spec build_context(map(), keyword() | list()) :: map()
  defp build_context(fields, headers) do
    %{
      organization_id: parse_id(fields["organization_id"]),
      flow_id: parse_id(fields["flow_id"]),
      contact_id: parse_id(fields["contact_id"]),
      webhook_log_id: parse_id(fields["webhook_log_id"]),
      headers: headers
    }
  end

  @spec parse_id(any()) :: non_neg_integer() | nil
  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Glific.parse_maybe_integer(id) do
      {:ok, parsed} -> parsed
      :error -> nil
    end
  end

  defp parse_id(_), do: nil
end
