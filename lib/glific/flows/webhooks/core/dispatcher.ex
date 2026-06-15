defmodule Glific.Flows.Webhooks.Dispatcher do
  @moduledoc """
  Single entry point for invoking a flow webhook by name.

  Looks the name up in `Glific.Flows.Webhooks.Registry`, builds a context map,
  and runs the webhook's `call/2` inside `Glific.Flows.Webhooks.Instrumentation.around/3`.

  For migrated sync webhooks that return `{:ok, value}` / `{:error, message}`,
  the dispatcher applies `Glific.Flows.Webhooks.ResultTranslator.to_legacy_structure/2`
  so the flow engine receives a results map on success and a bare string on failure.

  Migration is incremental: `Glific.Clients.CommonWebhook.webhook/2,3` keeps
  its existing per-name clauses, but the body of a migrated webhook's clause
  shrinks to a `dispatch_named/3` call here. The org-fallback chain in
  `Glific.Clients.webhook/3` is unchanged — non-CommonWebhook webhooks (the
  org-specific client modules like `Glific.Clients.Sol`, `Avanti`, etc.) are
  still resolved exactly as today.
  """

  alias Glific.Flows.{Action, FlowContext}
  alias Glific.Flows.Webhooks.{Instrumentation, Registry, ResultTranslator}
  alias Glific.Messages.Message

  @doc """
  Dispatch a webhook by `name` (the string as it appears in flow JSON URLs),
  with the parsed `fields` map and optional `headers`.

  Wraps the call in instrumentation and, when needed, flow-routing translation.
  """
  @spec dispatch_named(String.t(), map(), keyword() | list()) :: any()
  def dispatch_named(name, fields, headers \\ []) when is_binary(name) and is_map(fields) do
    module = Registry.lookup!(name)
    ctx = build_context(fields, headers)

    Instrumentation.around(module, ctx, fn ->
      module.call(fields, ctx)
      |> ResultTranslator.to_legacy_structure(module)
    end)
  end

  @doc """
  Dispatch an async webhook by node URL, wrapping the call with `Instrumentation.around_async/3`.

  Looks up the module in the Registry, builds a context map that includes `:action` and
  `:flow_context`, then delegates to `Instrumentation.around_async/3` which times the
  call and reports immediate failures to AppSignal.

  Returns the async tuple unchanged: `{:wait, context, []}` or `{:ok, context, [msg]}`.
  """
  @spec dispatch_async(String.t(), Action.t(), FlowContext.t()) ::
          {:wait | :ok, FlowContext.t(), [Message.t()]}
  def dispatch_async(url, action, context)
      when is_binary(url) do
    module = Registry.lookup!(url)

    ctx = %{
      organization_id: context.organization_id,
      action: action,
      flow_context: context,
      flow_id: context.flow_id,
      contact_id: context.contact_id,
      flow_context_id: context.id
    }

    Instrumentation.around_async(module, ctx, fn -> module.call(%{}, ctx) end)
  end

  # Builds the minimal ctx that Instrumentation needs (organization_id for
  # AppSignal tags). Per-webhook modules can pull anything else they need
  # from the fields map; richer ctx (flow_context, action) lands when async
  # webhooks migrate.
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
