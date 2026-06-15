defmodule Glific.Flows.Webhooks.SpeechToText do
  @moduledoc """
  Async webhook implementation for the `speech_to_text` flow node.

  Parks the flow in the await state and enqueues a `Glific.ThirdParty.Kaapi.SttTtsWorker`
  job to perform the Kaapi STT call. The flow is resumed by a Kaapi callback to
  `GlificWeb.Flows.FlowResumeController.flow_resume/2`.

  `name/0` returns `"speech_to_text"` — the URL string as it appears in deployed flow JSON.
  Since the node URL equals the observability webhook_name, no `webhook_name/0` override is
  needed.
  """

  use Glific.Flows.Webhooks.Async, name: "speech_to_text"

  alias Glific.Flows.Webhooks.AsyncSupport
  alias Glific.Flows.Webhooks.Behaviour

  @doc """
  Delegates to `AsyncSupport.enqueue_stt_tts/3` with the `"speech_to_text"` webhook name.

  Returns `{:wait, context, []}` on success (flow parked) or
  `{:ok, context, [failure_msg]}` on immediate failure (missing Kaapi creds, invalid body,
  enqueue error).
  """
  @impl true
  @spec call(map(), Behaviour.ctx()) :: Behaviour.async_result()
  def call(_fields, %{action: action, flow_context: context}) do
    AsyncSupport.enqueue_stt_tts(action, context, "speech_to_text")
  end

  @doc """
  Standard callback handler: returns `{:ok, response}` so the response map is merged into
  the flow context results by `FlowResumeController`.
  """
  @impl true
  @spec handle_resume(map(), Behaviour.ctx()) :: {:ok | :error, map()}
  def handle_resume(result, _ctx) do
    {:ok, result}
  end
end
