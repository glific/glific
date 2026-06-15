defmodule Glific.Flows.Webhooks.UnifiedLlm do
  @moduledoc """
  Async webhook implementation for the `filesearch-gpt` flow node.

  Parks the flow in the await state and dispatches a synchronous call to `CommonWebhook`
  which in turn makes an async request to the Kaapi unified LLM API
  (`/api/v1/llm/call`). Kaapi posts the result to the flow_resume callback URL embedded
  in `request_metadata`.

  The flow node URL in deployed flow JSON is `"filesearch-gpt"` — that is what `name/0`
  returns and what is used as the Registry key. However the Kaapi callback
  `request_metadata.webhook_name` (and all AppSignal metric tags) uses
  `"unified-llm-call"`, which is returned by `webhook_name/0`.
  """

  use Glific.Flows.Webhooks.Async, name: "filesearch-gpt"

  alias Glific.Flows.Webhooks.AsyncSupport
  alias Glific.Flows.Webhooks.Behaviour

  @doc """
  Observability/callback webhook name. Differs from `name/0` (`"filesearch-gpt"`) so that
  AppSignal metrics, Kaapi `request_metadata.webhook_name`, and callback routing use the
  stable `"unified-llm-call"` string even if the flow node URL ever changes.
  """
  @spec webhook_name() :: String.t()
  @impl true
  def webhook_name, do: "unified-llm-call"

  @doc """
  Delegates to `AsyncSupport.unified_llm_and_wait/3` with the `"unified-llm-call"`
  webhook name.

  Returns `{:wait, context, []}` on success (flow parked) or
  `{:ok, context, [failure_msg]}` on immediate failure (missing Kaapi creds, no active
  config version, invalid body, Kaapi HTTP error).
  """
  @impl true
  @spec call(map(), Behaviour.ctx()) :: Behaviour.async_result()
  def call(_fields, %{action: action, flow_context: context}) do
    AsyncSupport.unified_llm_and_wait(action, context, "unified-llm-call")
  end

  @doc """
  Standard callback handler: returns `{:ok, response}` (the parsed callback) unchanged so
  it is merged into the flow context results by `FlowResumeController`.
  """
  @impl true
  @spec handle_resume(map(), Behaviour.ctx()) :: {:ok | :error, map()}
  def handle_resume(response, _ctx) do
    {:ok, response}
  end
end
