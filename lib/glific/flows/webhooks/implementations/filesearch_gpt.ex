defmodule Glific.Flows.Webhooks.FilesearchGpt do
  @moduledoc """
  Async webhook implementation for the `filesearch-gpt` flow node (Kaapi unified LLM call).

  Runs inside the `Glific.Flows.Webhook` Oban worker (worker phase): it injects the org
  Kaapi API key, fires the async LLM request to `/api/v1/llm/call`, and returns the Kaapi
  ack. Kaapi POSTs the answer to `GlificWeb.Flows.FlowResumeController.flow_resume/2`, which
  resumes the parked flow.
  """

  use Glific.Flows.Webhooks.Async, name: "filesearch-gpt"

  alias Glific.Flows.Webhooks.Behaviour
  alias Glific.Flows.Webhooks.Kaapi, as: KaapiSupport
  alias Glific.ThirdParty.Kaapi

  @doc """
  Fires the async Kaapi LLM request. Fetches the org Kaapi API key, builds the signed
  callback metadata, and dispatches via `KaapiSupport.call_llm/4`. Returns the ack map
  (`%{success: …}`); `%{success: false, reason: "Kaapi is not active"}` when unconfigured.
  """
  @impl true
  @spec call(map(), Behaviour.ctx()) :: map()
  def call(fields, _ctx) do
    with {:ok, {organization_id, flow_id, contact_id}} <-
           KaapiSupport.parse_flow_fields(fields),
         {:ok, %{"api_key" => api_key}} when is_binary(api_key) <-
           Kaapi.fetch_kaapi_creds(organization_id) do
      {callback_url, request_metadata} =
        KaapiSupport.build_flow_resume_metadata(organization_id, flow_id, contact_id, fields)

      request_metadata =
        Map.merge(request_metadata, %{call_type: "llm", webhook_name: name()})

      KaapiSupport.call_llm(fields, [{"X-API-KEY", api_key}], callback_url, request_metadata)
    else
      {:error, error_type, reason} when is_atom(error_type) ->
        %{success: false, reason: reason, error_type: error_type}

      # An unconfigured org: fetch_kaapi_creds returns {:error, "Kaapi is not active"} — a
      # provisioning gap, so name it :missing_api_key (→ system) rather than leave it unjudged.
      {:error, reason} when is_binary(reason) ->
        %{success: false, reason: reason, error_type: :missing_api_key}

      # Any other shape (e.g. a creds row carrying no usable api_key) is genuinely unexpected —
      # fail safe to a generic system error instead of guessing a specific cause.
      _ ->
        %{success: false, reason: "Unexpected Kaapi dispatch failure", error_type: :unknown}
    end
  end
end
