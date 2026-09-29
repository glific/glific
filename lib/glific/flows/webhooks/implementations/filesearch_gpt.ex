defmodule Glific.Flows.Webhooks.FilesearchGpt do
  @moduledoc """
  Async webhook implementation for the `filesearch-gpt` flow node (Kaapi unified LLM call).
  Kaapi POSTs the answer to `FlowResumeController.flow_resume/2`, which resumes the parked flow.
  """

  use Glific.Flows.Webhooks.Async, name: "filesearch-gpt"

  alias Glific.Flows.Webhooks.Behaviour
  alias Glific.Flows.Webhooks.Kaapi, as: KaapiSupport
  alias Glific.ThirdParty.Kaapi

  @doc "Fires the async Kaapi LLM request."
  @impl true
  @spec call(map(), Behaviour.ctx()) :: Behaviour.result()
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
      |> KaapiSupport.to_result()
    else
      {:error, _error_type, _reason} = error ->
        error

      # unconfigured org (fetch_kaapi_creds -> {:error, binary}): a provisioning gap -> system
      {:error, reason} when is_binary(reason) ->
        {:error, :missing_api_key, reason}

      _ ->
        {:error, :unknown, "Unexpected Kaapi dispatch failure"}
    end
  end
end
