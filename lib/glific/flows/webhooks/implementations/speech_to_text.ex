defmodule Glific.Flows.Webhooks.SpeechToText do
  @moduledoc """
  Async webhook implementation for the `speech_to_text` flow node. Kaapi POSTs the transcription
  to `FlowResumeController.flow_resume/2`, which resumes the parked flow.
  """

  use Glific.Flows.Webhooks.Async, name: "speech_to_text"

  alias Glific.Flows.Webhooks.Behaviour
  alias Glific.Flows.Webhooks.Kaapi, as: KaapiSupport
  alias Glific.ThirdParty.Kaapi

  @doc """
  Fires the Kaapi STT request, enforcing the shared per-org STT/TTS rate limit and media
  validation first. Returns the Kaapi ack map (`%{success: …}`).
  """
  @impl true
  @spec call(map(), Behaviour.ctx()) :: Behaviour.result()
  def call(fields, _ctx) do
    speech = fields["speech"]

    with {:ok, {organization_id, flow_id, contact_id}} <-
           KaapiSupport.parse_flow_fields(fields),
         :ok <- KaapiSupport.check_rate_limit(organization_id),
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

      Kaapi.speech_to_text(speech, callback_url, request_metadata, organization_id, stt_opts)
      |> KaapiSupport.to_result()
    else
      {:snooze, _seconds} = snooze -> snooze
      {:error, _error_type, _reason} = error -> error
    end
  end
end
