defmodule Glific.Flows.Webhooks.Request do
  @moduledoc """
  Shared request-building helpers for flow webhooks, used by `Glific.Flows.Webhook`
  when enqueuing a webhook node: creating the `WebhookLog` row, interpolating the
  action body/headers/URL against the flow context, and signing the payload.

  These are plain helpers — dispatch, instrumentation, and flow-resume handling live
  in `Glific.Flows.Webhooks.{Dispatcher, Instrumentation}` and `Glific.Flows.Webhook`.
  """

  use Gettext, backend: GlificWeb.Gettext

  alias Glific.Flows.{Action, FlowContext, MessageVarParser, WebhookLog}
  alias Glific.Flows.Webhook.HeaderRedactor

  @doc """
  Creates a WebhookLog row for the given action and context. Called before
  enqueueing the webhook job so the log id can be embedded in the job args and
  callback metadata.
  """
  @spec create_log(Action.t(), map(), map(), FlowContext.t()) :: WebhookLog.t()
  def create_log(action, body, headers, context) do
    {:ok, webhook_log} =
      %{
        request_json: body,
        request_headers: HeaderRedactor.redact(headers),
        url: action.url,
        method: action.method,
        organization_id: context.organization_id,
        flow_id: context.flow_id,
        contact_id: context.contact_id,
        wa_group_id: context.wa_group_id,
        flow_context_id: context.id
      }
      |> WebhookLog.create_webhook_log()

    webhook_log
  end

  @doc """
  Builds the request body for a webhook action by decoding and interpolating the
  action's JSON body template with flow context variables.

  Returns `{fields_map, json_string}` on success or `{:error, message}` on failure.
  """
  @spec create_body(FlowContext.t(), String.t()) :: {map(), String.t()} | {:error, String.t()}
  def create_body(_context, action_body) when action_body in [nil, ""], do: {%{}, "{}"}

  def create_body(context, action_body) do
    case Jason.decode(action_body) do
      {:ok, action_body_map} ->
        do_create_body(context, action_body_map)

      _ ->
        # Don't log the raw body — it may contain user data.
        Glific.log_error("Error in decoding webhook body", false)

        {:error,
         dgettext(
           "errors",
           "Error in decoding webhook body. Please check the json body in floweditor"
         )}
    end
  end

  @doc """
  Parses the action's header and URL templates against flow context variables.
  Returns `%{header: map(), url: String.t()}`.
  """
  @spec parse_header_and_url(Action.t(), FlowContext.t()) :: map()
  def parse_header_and_url(action, context) do
    fields = FlowContext.get_vars_to_parse(context)
    header = MessageVarParser.parse_map(action.headers, fields)
    url = MessageVarParser.parse(action.url, fields)
    %{header: header, url: url}
  end

  @doc """
  Adds an HMAC signature header to the given headers map. Used to authenticate
  webhook callbacks.
  """
  @spec add_signature(map() | nil, non_neg_integer(), String.t()) :: map()
  def add_signature(headers, organization_id, body) do
    now = System.system_time(:second)
    sig = "t=#{now},v1=#{Glific.signature(organization_id, body, now)}"
    Map.put(headers || %{}, :"X-Glific-Signature", sig)
  end

  # ---- Private helpers --------------------------------------------------

  @spec do_create_body(FlowContext.t(), map()) :: {map(), String.t()} | {:error, String.t()}
  defp do_create_body(context, action_body_map) do
    default_payload = %{
      contact: get_contact(context),
      wa_group: get_wa_group(context),
      results: context.results,
      flow: %{name: context.flow.name, id: context.flow.id}
    }

    fields = FlowContext.get_vars_to_parse(context)

    action_body_map =
      MessageVarParser.parse_map(action_body_map, fields)
      |> Enum.map(fn
        {k, "@contact"} -> {k, default_payload.contact}
        {k, "@wa_group"} -> {k, default_payload.wa_group}
        {k, "@results"} -> {k, default_payload.results}
        {k, v} -> {k, v}
      end)
      |> Enum.into(%{})
      |> Map.put("organization_id", context.organization_id)

    case Jason.encode(action_body_map) do
      {:ok, action_body} ->
        {action_body_map, action_body}

      _ ->
        # Don't log the raw body — it may contain user data.
        Glific.log_error("Error in encoding webhook body", false)

        {:error,
         dgettext(
           "errors",
           "Error in encoding webhook body. Please check the json body in floweditor"
         )}
    end
  end

  @spec get_contact(FlowContext.t()) :: map()
  defp get_contact(%FlowContext{contact_id: contact_id} = context) when contact_id != nil do
    %{
      id: context.contact.id,
      name: context.contact.name,
      phone: context.contact.phone,
      fields: context.contact.fields
    }
  end

  defp get_contact(_context), do: %{}

  @spec get_wa_group(FlowContext.t()) :: map()
  defp get_wa_group(%FlowContext{wa_group_id: wa_group_id} = context)
       when wa_group_id != nil do
    %{
      id: context.wa_group.id,
      label: context.wa_group.label,
      wa_managed_phone_id: context.wa_group.wa_managed_phone_id
    }
  end

  defp get_wa_group(_context), do: %{}
end
