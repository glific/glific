defmodule Glific.Flows.Webhooks.SpeechToText do
  @moduledoc """
  Async webhook implementation for the `speech_to_text` flow node.

  Runs inside the `Glific.Flows.Webhook` Oban worker (worker phase): it fires the
  Kaapi STT request and returns the Kaapi ack. Kaapi POSTs the transcription to
  `GlificWeb.Flows.FlowResumeController.flow_resume/2`, which resumes the parked flow.

  A successful ack (`%{success: true}`) means "Kaapi accepted the request" — the flow
  stays parked until the callback arrives. A failure routes the flow to the Failure branch.
  """

  use Glific.Flows.Webhooks.Async, name: "speech_to_text"

  alias Glific.Flows.Webhooks.Behaviour
  alias Glific.Flows.Webhooks.Kaapi, as: KaapiSupport
  alias Glific.ThirdParty.Kaapi

  @doc """
  Fires the Kaapi STT request. Validates the speech URL, builds the signed callback
  metadata, and dispatches to Kaapi. Returns the Kaapi ack map (`%{success: …}`).
  """
  @impl true
  @spec call(map(), Behaviour.ctx()) :: map()
  def call(fields, _ctx) do
    speech = fields["speech"]

    with {:ok, {organization_id, flow_id, contact_id}} <-
           KaapiSupport.parse_flow_fields(fields),
         :ok <- KaapiSupport.validate_media(speech) do
      {callback_url, request_metadata} =
        KaapiSupport.build_flow_resume_metadata(organization_id, flow_id, contact_id, fields)

      request_metadata =
        Map.merge(request_metadata, %{call_type: "stt", webhook_name: "speech_to_text"})

      stt_opts = %{
        provider: fields["provider"],
        model: fields["model"],
        language: fields["language"],
        output_language: fields["output_language"]
      }

      Glific.Metrics.increment("Kaapi STT Call", organization_id)
      Kaapi.speech_to_text(speech, callback_url, request_metadata, organization_id, stt_opts)
    else
      {:error, reason} -> %{success: false, reason: reason}
    end
  end

  @doc "An invalid/missing media URL is user input (config); a keyless org is a provisioning gap (system)."
  @impl true
  @spec error_class(map()) :: :config | :system | nil
  def error_class(%{reason: "Media URL is" <> _}), do: :config
  def error_class(%{reason: "Kaapi is not active" <> _}), do: :system
  def error_class(_result), do: nil
end
