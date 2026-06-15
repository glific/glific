defmodule Glific.Flows.Webhooks.UnifiedVoiceLlm do
  @moduledoc """
  Async webhook implementation for the `voice-filesearch-gpt` flow node.

  Parks the flow in the await state and dispatches via `CommonWebhook` to the Kaapi
  unified voice LLM pipeline (STT → LLM → callback). The Kaapi response arrives at
  `GlificWeb.Flows.FlowResumeController.voice_flow_resume/2`.

  The flow node URL in deployed flow JSON is `"voice-filesearch-gpt"` — that is what
  `name/0` returns and what is used as the Registry key. The Kaapi callback
  `request_metadata.webhook_name` (and all AppSignal metric tags) uses
  `"unified-voice-llm-call"`, which is returned by `webhook_name/0`.

  This module overrides `handle_resume/2` to apply `CommonWebhook.voice_post_process/3`
  (NMT + TTS) before the flow is resumed, producing `translated_text` and `media_url`
  fields in the response map.
  """

  use Glific.Flows.Webhooks.Async, name: "voice-filesearch-gpt"

  alias Glific.Clients.CommonWebhook
  alias Glific.Flows.Webhooks.AsyncSupport
  alias Glific.Flows.Webhooks.Behaviour

  @doc """
  Observability/callback webhook name. Differs from `name/0` (`"voice-filesearch-gpt"`)
  so that AppSignal metrics, Kaapi `request_metadata.webhook_name`, and callback routing
  use the stable `"unified-voice-llm-call"` string.
  """
  @spec webhook_name() :: String.t()
  @impl true
  def webhook_name, do: "unified-voice-llm-call"

  @doc """
  Delegates to `AsyncSupport.unified_llm_and_wait/3` with the `"unified-voice-llm-call"`
  webhook name.

  Returns `{:wait, context, []}` on success (flow parked) or
  `{:ok, context, [failure_msg]}` on immediate failure (missing Kaapi creds, no active
  config version, invalid body, Kaapi HTTP error).
  """
  @impl true
  @spec call(map(), Behaviour.ctx()) :: Behaviour.async_result()
  def call(_fields, %{action: action, flow_context: context}) do
    AsyncSupport.unified_llm_and_wait(action, context, "unified-voice-llm-call")
  end

  @doc """
  Voice callback handler. Applies NMT + TTS (`CommonWebhook.voice_post_process/3`) to the
  parsed Kaapi LLM `response`, producing `translated_text` and `media_url` fields that the
  flow can use for the voice reply. Returns `{:ok, voice_response}`.

  `response` is the parsed callback (from `parse_callback_response/1`); `ctx` carries
  `organization_id` (for org-level GCS/Bhasini config) and `success` (the raw callback
  success flag, which drives whether `voice_post_process` translates the real reply or the
  failure text).
  """
  @impl true
  @spec handle_resume(map(), Behaviour.ctx()) :: {:ok | :error, map()}
  def handle_resume(response, ctx) do
    organization_id = Map.get(ctx, :organization_id)
    success = Map.get(ctx, :success)
    voice_response = CommonWebhook.voice_post_process(organization_id, success, response)
    {:ok, voice_response}
  end
end
