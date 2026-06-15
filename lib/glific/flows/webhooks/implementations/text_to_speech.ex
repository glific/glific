defmodule Glific.Flows.Webhooks.TextToSpeech do
  @moduledoc """
  Async webhook implementation for the `text_to_speech` flow node.

  Runs inside the `Glific.Flows.Webhook` Oban worker (worker phase): it fires the
  Kaapi TTS request and returns the Kaapi ack. Kaapi POSTs the generated audio to
  `GlificWeb.Flows.FlowResumeController.flow_resume/2`, which resumes the parked flow.
  """

  use Glific.Flows.Webhooks.Async, name: "text_to_speech"

  alias Glific.Flows.Webhooks.Behaviour
  alias Glific.Flows.Webhooks.Kaapi, as: KaapiSupport
  alias Glific.ThirdParty.Kaapi

  @doc """
  Fires the Kaapi TTS request. Builds the signed callback metadata and dispatches to
  Kaapi. Returns the Kaapi ack map (`%{success: …}`).
  """
  @impl true
  @spec call(map(), Behaviour.ctx()) :: map()
  def call(fields, _ctx) do
    case KaapiSupport.parse_flow_fields(fields) do
      {:ok, {organization_id, flow_id, contact_id}} ->
        {callback_url, request_metadata} =
          KaapiSupport.build_flow_resume_metadata(organization_id, flow_id, contact_id, fields)

        request_metadata =
          Map.merge(request_metadata, %{call_type: "tts", webhook_name: "text_to_speech"})

        tts_opts = %{
          provider: fields["provider"],
          model: fields["model"],
          language: fields["language"],
          voice: fields["voice"]
        }

        Glific.Metrics.increment("Kaapi TTS Call", organization_id)

        Kaapi.text_to_speech(
          organization_id,
          fields["text"],
          callback_url,
          request_metadata,
          tts_opts
        )

      {:error, reason} ->
        %{success: false, reason: reason}
    end
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
