defmodule Glific.Flows.Webhooks.TextToSpeech do
  @moduledoc """
  Async webhook implementation for the `text_to_speech` flow node. Kaapi POSTs the generated
  audio to `FlowResumeController.flow_resume/2`, which resumes the parked flow.
  """

  use Glific.Flows.Webhooks.Async, name: "text_to_speech"

  alias Glific.Flows.Webhooks.Behaviour
  alias Glific.Flows.Webhooks.Kaapi, as: KaapiSupport
  alias Glific.ThirdParty.Kaapi

  @doc """
  Fires the Kaapi TTS request, enforcing the shared per-org STT/TTS rate limit first. Returns
  the Kaapi ack map (`%{success: …}`).
  """
  @impl true
  @spec call(map(), Behaviour.ctx()) :: Behaviour.result()
  def call(fields, _ctx) do
    with {:ok, {organization_id, flow_id, contact_id}} <-
           KaapiSupport.parse_flow_fields(fields),
         :ok <- KaapiSupport.check_rate_limit(organization_id) do
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

      Kaapi.text_to_speech(
        organization_id,
        fields["text"],
        callback_url,
        request_metadata,
        tts_opts
      )
      |> KaapiSupport.to_result()
    else
      {:snooze, _seconds} = snooze -> snooze
      {:error, _error_type, _reason} = error -> error
    end
  end
end
