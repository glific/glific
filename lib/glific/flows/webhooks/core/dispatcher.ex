defmodule Glific.Flows.Webhooks.Dispatcher do
  @moduledoc """
  Single entry point for invoking a flow webhook by name.

  Looks the name up in `Glific.Flows.Webhooks.Registry`, builds a context map,
  and runs the webhook's `call/2` inside `Glific.Flows.Webhooks.Instrumentation.around/3`.

  Migration is incremental: `Glific.Clients.CommonWebhook.webhook/2,3` keeps
  its existing per-name clauses, but the body of a migrated webhook's clause
  shrinks to a `dispatch_named/3` call here. The org-fallback chain in
  `Glific.Clients.webhook/3` is unchanged — non-CommonWebhook webhooks (the
  org-specific client modules like `Glific.Clients.Sol`, `Avanti`, etc.) are
  still resolved exactly as today.
  """

  alias Glific.Flows.Webhooks.{Instrumentation, Registry}

  @doc """
  Dispatch a webhook by `name` (the string as it appears in flow JSON URLs),
  with the parsed `fields` map and optional `headers`.

  Wraps the call in instrumentation. Returns whatever the webhook returns.
  """
  @spec dispatch_named(String.t(), map(), keyword() | list()) :: any()
  def dispatch_named(name, fields, headers \\ []) when is_binary(name) and is_map(fields) do
    module = Registry.lookup!(name)
    ctx = build_ctx(fields, headers)

    Instrumentation.around(module, ctx, fn ->
      apply(module, :call, [fields, ctx])
    end)
  end

  # Builds the minimal ctx that Instrumentation needs (organization_id for
  # AppSignal tags). Per-webhook modules can pull anything else they need
  # from the fields map; richer ctx (flow_context, action) lands when async
  # webhooks migrate.
  @spec build_ctx(map(), keyword() | list()) :: map()
  defp build_ctx(fields, headers) do
    org_id =
      case fields["organization_id"] do
        nil -> nil
        id when is_integer(id) -> id
        id when is_binary(id) -> Glific.parse_maybe_integer(id) |> elem(1)
        _ -> nil
      end

    %{
      organization_id: org_id,
      headers: headers
    }
  end
end
