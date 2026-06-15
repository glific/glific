defmodule Glific.Flows.Webhooks.AsyncSupport do
  @moduledoc """
  Shared plumbing for asynchronous Kaapi webhooks (STT, TTS, unified-llm-call,
  unified-voice-llm-call).

  Provides two public entry points consumed by the four `Glific.Flows.Webhooks.*`
  implementation modules:

  - `enqueue_stt_tts/3` — for `speech_to_text` and `text_to_speech` nodes: checks
    Kaapi credentials, builds the webhook log, enriches the fields map, and enqueues
    a `Glific.ThirdParty.Kaapi.SttTtsWorker` job.

  - `unified_llm_and_wait/3` — for `filesearch-gpt` and `voice-filesearch-gpt` nodes:
    fetches the Kaapi API key, builds the webhook log, adds the X-API-KEY header, and
    calls `CommonWebhook.webhook/3` synchronously to dispatch the async LLM request to
    Kaapi (Kaapi will POST the result to the flow_resume callback URL).

  Both entry points return:
  - `{:wait, context, []}` — flow parked; Kaapi will callback.
  - `{:ok, context, [failure_msg]}` — immediate failure (missing creds, bad body, enqueue
    error, Kaapi sync-failure). The flow continues on the Failure branch without waiting.

  Cross-cutting concerns (failure reporting to AppSignal, latency telemetry, WebhookLog row
  creation) are handled by `Glific.Flows.Webhooks.Instrumentation` (at dispatch time) and
  by `GlificWeb.Flows.FlowResumeController` (at callback time). This module does NOT call
  AppSignal directly.
  """

  use Gettext, backend: GlificWeb.Gettext

  require Logger

  alias Glific.Clients.CommonWebhook
  alias Glific.Flows.{Action, FlowContext, MessageVarParser, Webhook, WebhookLog}
  alias Glific.Flows.Webhook.HeaderRedactor
  alias Glific.Messages
  alias Glific.Messages.Message
  alias Glific.ThirdParty.Kaapi
  alias Glific.ThirdParty.Kaapi.SttTtsWorker

  # ---- Public API -------------------------------------------------------

  @doc """
  Shared entry point for `speech_to_text` and `text_to_speech` async nodes.

  Checks Kaapi credentials, builds a WebhookLog row, enriches the fields map with
  metadata required by `SttTtsWorker`, and enqueues the job. If credentials are
  missing or body parsing fails the function returns an immediate-failure tuple so
  the framework can route the flow to the Failure branch.
  """
  @spec enqueue_stt_tts(Action.t(), FlowContext.t(), String.t()) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]}
  def enqueue_stt_tts(action, context, webhook_name) do
    case Kaapi.fetch_kaapi_creds(context.organization_id) do
      {:ok, _secrets} ->
        do_enqueue_stt_tts(action, context, webhook_name)

      {:error, _reason} ->
        kaapi_not_active_error(action, context)
    end
  end

  @doc """
  Shared entry point for `filesearch-gpt` and `voice-filesearch-gpt` async nodes.

  Fetches the Kaapi API key, injects it as `X-API-KEY` into the action headers, then
  calls `CommonWebhook.webhook/3` which dispatches the async LLM call to Kaapi. Kaapi
  will POST the result to the flow_resume callback URL embedded in `request_metadata`.
  """
  @spec unified_llm_and_wait(Action.t(), FlowContext.t(), String.t()) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]}
  def unified_llm_and_wait(action, context, webhook_name) do
    case Kaapi.fetch_kaapi_creds(context.organization_id) do
      {:ok, %{"api_key" => api_key}} when is_binary(api_key) ->
        updated_action = %{action | headers: Map.put(action.headers, "X-API-KEY", api_key)}
        do_unified_llm_call(updated_action, context, webhook_name)

      _ ->
        kaapi_not_active_error(action, context)
    end
  end

  # ---- Helpers used by Glific.Flows.Webhook (delegated public fns) ----

  @doc """
  Creates a WebhookLog row for the given action and context. Called before
  enqueueing the actual Kaapi request so the log id can be embedded in the
  job args and callback metadata.
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
        Logger.info("Error in decoding webhook body #{inspect(action_body)}.")

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
  Kaapi callbacks.
  """
  @spec add_signature(map() | nil, non_neg_integer(), String.t()) :: map()
  def add_signature(headers, organization_id, body) do
    now = System.system_time(:second)
    sig = "t=#{now},v1=#{Glific.signature(organization_id, body, now)}"
    Map.put(headers, :"X-Glific-Signature", sig)
  end

  @doc """
  Parks the flow context in the await state for `wait_time` seconds. Returns
  `{:wait, updated_context, []}` — the `:wait` tuple consumed by the flow engine.
  """
  @spec update_context_for_wait(FlowContext.t(), integer()) :: {:wait, FlowContext.t(), []}
  def update_context_for_wait(context, wait_time) do
    {:ok, context} =
      FlowContext.update_flow_context(
        context,
        %{
          wakeup_at: DateTime.add(DateTime.utc_now(), wait_time),
          is_background_flow: context.flow.is_background,
          is_await_result: true
        }
      )

    {:wait, context, []}
  end

  # ---- Private helpers --------------------------------------------------

  @spec do_enqueue_stt_tts(Action.t(), FlowContext.t(), String.t()) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]}
  defp do_enqueue_stt_tts(action, context, webhook_name) do
    failure_message = Messages.create_temp_message(context.organization_id, "Failure")

    case create_body(context, action.body) do
      {:error, message} ->
        webhook_log = create_log(action, %{}, action.headers, context)
        update_webhook_log(webhook_log, message)
        {:ok, context, [failure_message]}

      {fields, _body} ->
        webhook_log = create_log(action, fields, action.headers, context)

        fields =
          fields
          |> Map.put("webhook_log_id", webhook_log.id)
          |> Map.put("result_name", action.result_name)
          |> Map.put("flow_id", context.flow_id)
          |> Map.put("contact_id", context.contact_id)

        case SttTtsWorker.enqueue(
               webhook_name,
               fields,
               webhook_log.id,
               context.id,
               context.organization_id
             ) do
          {:ok, _job} ->
            wait_time = action.wait_time || 60
            update_context_for_wait(context, wait_time)

          {:error, changeset} ->
            update_webhook_log(webhook_log.id, inspect(changeset))
            {:ok, context, [failure_message]}
        end
    end
  end

  @spec do_unified_llm_call(Action.t(), FlowContext.t(), String.t()) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]}
  defp do_unified_llm_call(action, context, webhook_name) do
    parsed_attrs = parse_header_and_url(action, context)
    failure_message = Messages.create_temp_message(context.organization_id, "Failure")

    case create_body(context, action.body) do
      {:error, message} ->
        webhook_log = create_log(action, %{}, action.headers, context)
        update_webhook_log(webhook_log, message)
        {:ok, context, [failure_message]}

      {fields, body} ->
        webhook_log = create_log(action, fields, action.headers, context)

        params = %{
          action: action,
          context: context,
          webhook_log: webhook_log,
          fields: fields,
          body: body,
          headers: parsed_attrs.header
        }

        do_unified_llm_and_wait(params, failure_message, webhook_name)
    end
  end

  @spec do_unified_llm_and_wait(map(), Message.t(), String.t()) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]}
  defp do_unified_llm_and_wait(params, failure_message, webhook_name) do
    webhook_log_id = params.webhook_log.id

    fields =
      params.fields
      |> Map.put("webhook_log_id", webhook_log_id)
      |> Map.put("result_name", params.action.result_name)
      |> Map.put("flow_id", params.context.flow_id)
      |> Map.put("contact_id", params.context.contact_id)

    headers =
      params.headers
      |> add_signature(params.context.organization_id, params.body)
      |> Enum.reduce([], fn {k, v}, acc -> acc ++ [{k, v}] end)

    process_unified_llm_call(%{
      webhook_log_id: webhook_log_id,
      fields: fields,
      headers: headers,
      action: params.action,
      context: params.context,
      failure_message: failure_message,
      webhook_name: webhook_name
    })
  end

  @spec process_unified_llm_call(map()) :: {:ok | :wait, FlowContext.t(), [Message.t()]}
  defp process_unified_llm_call(params) do
    response = CommonWebhook.webhook(params.webhook_name, params.fields, params.headers)

    case response do
      %{success: true, data: data} ->
        update_webhook_log(params.webhook_log_id, data)
        wait_time = params.action.wait_time || 60
        update_context_for_wait(params.context, wait_time)

      %{success: true} ->
        wait_time = params.action.wait_time || 60
        update_context_for_wait(params.context, wait_time)

      %{success: false, reason: data} ->
        update_webhook_log(params.webhook_log_id, data)
        {:ok, params.context, [params.failure_message]}

      _ ->
        update_webhook_log(params.webhook_log_id, "Something went wrong")
        {:ok, params.context, [params.failure_message]}
    end
  end

  # Returns an immediate failure tuple when Kaapi is not configured for the org.
  # Does NOT report to AppSignal — that is the caller's (Instrumentation's) responsibility.
  @spec kaapi_not_active_error(Action.t(), FlowContext.t()) ::
          {:ok, FlowContext.t(), [Message.t()]}
  defp kaapi_not_active_error(action, context) do
    failure_message = Messages.create_temp_message(context.organization_id, "Failure")
    webhook_log = create_log(action, %{}, action.headers, context)
    update_webhook_log(webhook_log.id, "Kaapi is not active")
    {:ok, context, [failure_message]}
  end

  # Internal update_webhook_log — delegates to the legacy Webhook.update_log so
  # all WebhookLog mutation logic stays in one place.
  @spec update_webhook_log(WebhookLog.t() | non_neg_integer(), any()) :: any()
  defp update_webhook_log(webhook_log_or_id, message) do
    Webhook.update_log(webhook_log_or_id, message)
  end

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
        Logger.info("Error in encoding webhook body #{inspect(action_body_map)}.")

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
