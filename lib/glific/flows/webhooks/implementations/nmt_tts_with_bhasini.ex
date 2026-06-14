defmodule Glific.Flows.Webhooks.NmtTtsWithBhasini do
  @moduledoc """
  Migrated webhook for `nmt_tts_with_bhasini`.

  Translates text from a source language to a target language and then
  synthesises it to speech (NMT + TTS). When the source and target languages
  are the same, translation is skipped and only TTS is performed.

  Speech-engine routing:
  - `speech_engine == "bhashini"` — Gemini TTS
  - `speech_engine == "open_ai"` or language is English — OpenAI TTS
  - any other case — Gemini TTS

  Returns `{:ok, map()}` on success or `{:error, String.t()}` on failure.
  The centralised dispatcher handles AppSignal reporting; `ResultTranslator`
  encodes the tagged tuple into the map shape that the flow engine expects.

  Note: The private helpers `do_nmt_tts_with_bhasini/1`, `gemini_nmt_tts_call/5`,
  `handle_tts_only/4`, and `normalize_language/1` in `CommonWebhook` are preserved
  there because they are also called by `voice_post_process/3` (the unified-voice-llm-call
  copy webhook). This module contains independent copies of that logic.
  """

  use Glific.Flows.Webhooks.Sync, name: "nmt_tts_with_bhasini"

  alias Glific.Metrics
  alias Glific.OpenAI.ChatGPT
  alias Glific.Partners
  alias Glific.ThirdParty.Gemini

  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) ::
          {:ok, map()} | {:error, String.t()}
  def call(fields, ctx) do
    text = fields["text"]
    source_language = normalize_language(fields["source_language"])
    target_language = normalize_language(fields["target_language"])
    speech_engine = Map.get(fields, "speech_engine", "")

    if source_language == target_language do
      handle_tts_only(source_language, ctx.organization_id, text, speech_engine)
    else
      gemini_nmt_tts_call(source_language, target_language, ctx.organization_id, text,
        speech_engine: speech_engine
      )
    end
  end

  @spec gemini_nmt_tts_call(String.t(), String.t(), non_neg_integer(), String.t(), Keyword.t()) ::
          {:ok, map()} | {:error, String.t()}
  defp gemini_nmt_tts_call(source_language, target_language, org_id, text, opts) do
    organization = Partners.organization(org_id)
    services = organization.services["google_cloud_storage"]

    with false <- is_nil(services),
         true <- Gemini.valid_language?(source_language, target_language) do
      Metrics.increment("Gemini NMT TTS Call", org_id)

      translate_result(
        Gemini.nmt_text_to_speech(org_id, text, source_language, target_language, opts)
      )
    else
      true ->
        {:error, "GCS is disabled"}

      false ->
        {:error, "Language not supported in Gemini"}
    end
  end

  @spec handle_tts_only(String.t(), non_neg_integer(), String.t(), String.t()) ::
          {:ok, map()} | {:error, String.t()}
  defp handle_tts_only(language, org_id, text, speech_engine) do
    cond do
      speech_engine == "bhashini" ->
        Metrics.increment("Gemini NMT TTS Call", org_id)
        translate_result(Gemini.text_to_speech(org_id, text))

      speech_engine == "open_ai" || language == "english" ->
        translate_result(ChatGPT.text_to_speech_with_open_ai(org_id, text))

      true ->
        Metrics.increment("Gemini NMT TTS Call", org_id)
        translate_result(Gemini.text_to_speech(org_id, text))
    end
  end

  @spec normalize_language(String.t() | nil) :: String.t()
  defp normalize_language(nil), do: ""
  defp normalize_language(language), do: String.downcase(language)

  @spec translate_result(map()) :: {:ok, map()} | {:error, String.t()}
  defp translate_result(%{success: true} = result),
    do: {:ok, Map.delete(result, :success)}

  defp translate_result(%{success: false, reason: reason}),
    do: {:error, to_string(reason)}

  defp translate_result(%{success: false} = result),
    do: {:error, "NMT TTS failed: #{inspect(result)}"}

  defp translate_result(other),
    do: {:error, "Unexpected response from NMT TTS: #{inspect(other)}"}
end
