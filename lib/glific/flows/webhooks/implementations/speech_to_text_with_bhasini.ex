defmodule Glific.Flows.Webhooks.SpeechToTextWithBhasini do
  @moduledoc """
  Migrated webhook for `speech_to_text_with_bhasini`.

  Validates the contact and speech URL via `Glific.ASR.Bhasini.validate_params/1`,
  then delegates speech-to-text transcription to `Glific.ThirdParty.Gemini.speech_to_text/2`.

  Returns `{:ok, %{asr_response_text: String.t()}}` on success or
  `{:error, String.t()}` on failure. The centralised dispatcher handles
  AppSignal reporting; `ResultTranslator` encodes the tagged tuple into the
  map shape that the flow engine expects.

  Note: the private helper `do_speech_to_text_with_bhasini/1` in
  `Glific.Clients.CommonWebhook` is preserved because it is also called by
  the `unified-voice-llm-call` webhook, which has not yet been migrated.
  """

  use Glific.Flows.Webhooks.Sync, name: "speech_to_text_with_bhasini"

  alias Glific.ASR.Bhasini
  alias Glific.ThirdParty.Gemini
  alias Glific.Metrics

  @doc """
  Transcribe an audio file using the Bhasini/Gemini speech-to-text pipeline.

  Validates contact and audio URL via `Glific.ASR.Bhasini.validate_params/1`,
  increments a Gemini STT metric, then delegates to
  `Glific.ThirdParty.Gemini.speech_to_text/2`.

  Returns `{:ok, %{asr_response_text: String.t()}}` on success or
  `{:error, String.t()}` on failure.
  """
  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) ::
          {:ok, map()} | {:error, String.t()}
  def call(fields, ctx) do
    case Bhasini.validate_params(fields) do
      {:ok, contact} ->
        Metrics.increment("Gemini STT Call", contact.organization_id)
        translate_gemini_result(Gemini.speech_to_text(fields["speech"], ctx.organization_id))

      {:error, error} ->
        {:error, error}
    end
  end

  @spec translate_gemini_result(map()) :: {:ok, map()} | {:error, String.t()}
  defp translate_gemini_result(%{success: true} = result),
    do: {:ok, Map.delete(result, :success)}

  defp translate_gemini_result(%{success: false, asr_response_text: reason}),
    do: {:error, to_string(reason)}
end
