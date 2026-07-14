defmodule Glific.Flows.Webhooks.Dispatcher do
  @moduledoc """
  Single entry point for invoking a registered flow webhook by name: looks it up in the
  `Registry`, builds a context, and runs `call/2` inside `Instrumentation.around/3`. For migrated
  sync webhooks it then applies `ResultTranslator.to_legacy_structure/2` (map on success, string
  on failure); async result maps pass through. Only nodes registered in the `Registry` route here
  (org-specific client modules go via `Glific.Clients.webhook/2`).
  """

  alias Glific.Flows.Webhooks.{Instrumentation, Registry, ResultTranslator}

  @doc "Dispatch a registered webhook by name with the parsed fields (+ optional headers)."
  @spec dispatch(String.t(), map(), keyword() | list()) :: any()
  def dispatch(name, fields, headers \\ []) when is_binary(name) and is_map(fields) do
    module = Registry.lookup!(name)
    ctx = build_context(fields, headers)

    # Translation runs AFTER instrumentation so around/3 sees the raw typed result and classifies
    # from it; the flow engine only ever sees the translated legacy shape.
    module
    |> Instrumentation.around(ctx, fn -> module.call(fields, ctx) end)
    |> ResultTranslator.to_legacy_structure(module)
  end

  # Carry the flow-context ids from the fields onto ctx so a failure reported before the callback
  # (dispatch failure / crash) still tags contact/flow/webhook_log, like the callback path does.
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
