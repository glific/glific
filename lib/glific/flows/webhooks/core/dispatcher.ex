defmodule Glific.Flows.Webhooks.Dispatcher do
  @moduledoc """
  Single entry point for invoking a registered flow webhook by name.

  Looks the name up in `Glific.Flows.Webhooks.Registry`, builds a context map,
  and runs the webhook's `call/2` inside `Glific.Flows.Webhooks.Instrumentation.around/3`.
  The same entry serves both sync and async webhooks: every registered `call/2`
  returns a result map (or a `{:ok,_}`/`{:error,_}` tuple for the migrated sync
  webhooks). The flow engine, not the dispatcher, decides what to do with the
  result — async webhooks leave the flow parked on a successful ack (see
  `Glific.Flows.Webhook.perform/1`).

  For migrated sync webhooks that return `{:ok, value}` / `{:error, message}`,
  the dispatcher applies `Glific.Flows.Webhooks.ResultTranslator.to_legacy_structure/2`
  so the flow engine receives a results map on success and a bare string on failure;
  result maps (the async webhooks) pass through unchanged.

  Org-specific webhook functions (per-org client modules like `Glific.Clients.Sol`, `Avanti`,
  etc.) are resolved by `Glific.Clients.webhook/2` — only framework nodes registered in the
  `Registry` route through here.
  """

  alias Glific.Flows.Webhooks.{Instrumentation, Registry, ResultTranslator}

  @doc """
  Dispatch a webhook by `name` (the string as it appears in flow JSON URLs),
  with the parsed `fields` map and optional `headers`. Handles both sync and
  async webhooks.

  Wraps the call in instrumentation and, when needed, flow-routing translation.
  """
  @spec dispatch(String.t(), map(), keyword() | list()) :: any()
  def dispatch(name, fields, headers \\ []) when is_binary(name) and is_map(fields) do
    module = Registry.lookup!(name)
    ctx = build_context(fields, headers)

    # Translation runs AFTER instrumentation so Instrumentation.around/3 sees the raw
    # result — including a typed `{:error, ErrorType.t(), msg}` — and can classify from
    # the returned value without calling back into the module. The flow engine only ever
    # sees the translated legacy shape.
    module
    |> Instrumentation.around(ctx, fn -> module.call(fields, ctx) end)
    |> ResultTranslator.to_legacy_structure(module)
  end

  # Builds the minimal ctx that Instrumentation needs (organization_id for
  # AppSignal tags). Per-webhook modules pull anything else they need from the
  # fields map.
  @spec build_context(map(), keyword() | list()) :: map()
  defp build_context(fields, headers) do
    org_id =
      case fields["organization_id"] do
        nil ->
          nil

        id when is_integer(id) ->
          id

        id when is_binary(id) ->
          case Glific.parse_maybe_integer(id) do
            {:ok, parsed} -> parsed
            :error -> nil
          end

        _ ->
          nil
      end

    %{
      organization_id: org_id,
      headers: headers
    }
  end
end
