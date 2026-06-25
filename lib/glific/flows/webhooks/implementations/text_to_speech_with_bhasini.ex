defmodule Glific.Flows.Webhooks.TextToSpeechWithBhasini do
  @moduledoc """
  Migrated webhook for `text_to_speech_with_bhasini`.

  Routes text-to-speech synthesis to either OpenAI or Gemini based on the
  `speech_engine` field in the request and the contact's language:

  - `speech_engine == "open_ai"` — OpenAI TTS regardless of language
  - `speech_engine == "bhashini"` — Gemini TTS regardless of language
  - contact language is English — OpenAI TTS
  - any other language — Gemini TTS

  Returns `{:ok, map()}` on success or `{:error, String.t()}` on failure.
  The centralised dispatcher handles AppSignal reporting; `ResultTranslator`
  encodes the tagged tuple into the map shape that the flow engine expects.
  """

  use Glific.Flows.Webhooks.Sync, name: "text_to_speech_with_bhasini"

  alias Glific.Contacts
  alias Glific.Metrics
  alias Glific.OpenAI.ChatGPT
  alias Glific.ThirdParty.Gemini

  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) ::
          {:ok, map()} | {:error, String.t()}
  def call(fields, ctx) do
    text = fields["text"]
    contact_id_str = fields["contact"]["id"]

    case Glific.parse_maybe_integer(contact_id_str) do
      {:ok, contact_id} when is_integer(contact_id) ->
        do_call(fields, ctx, text, contact_id)

      _ ->
        {:error, "Invalid contact id: #{inspect(contact_id_str)}"}
    end
  end

  @spec do_call(map(), Glific.Flows.Webhooks.Behaviour.ctx(), String.t(), non_neg_integer()) ::
          {:ok, map()} | {:error, String.t()}
  defp do_call(fields, ctx, text, contact_id) do
    case Contacts.preload_contact_language(contact_id) do
      nil ->
        {:error, "Contact not found for id: #{contact_id}"}

      contact ->
        source_language =
          if contact.language, do: String.downcase(contact.language.label), else: ""

        speech_engine = Map.get(fields, "speech_engine", "")

        cond do
          speech_engine == "open_ai" ->
            translate_tts_result(ChatGPT.text_to_speech_with_open_ai(ctx.organization_id, text))

          speech_engine == "bhashini" ->
            Metrics.increment("Gemini TTS Call", ctx.organization_id)
            translate_tts_result(Gemini.text_to_speech(ctx.organization_id, text))

          source_language == "english" ->
            translate_tts_result(ChatGPT.text_to_speech_with_open_ai(ctx.organization_id, text))

          true ->
            Metrics.increment("Gemini TTS Call", ctx.organization_id)
            translate_tts_result(Gemini.text_to_speech(ctx.organization_id, text))
        end
    end
  end

  @spec translate_tts_result(map()) :: {:ok, map()} | {:error, String.t()}
  defp translate_tts_result(%{success: true} = result),
    do: {:ok, Map.delete(result, :success)}

  defp translate_tts_result(%{success: false, reason: reason}),
    do: {:error, to_string(reason)}

  defp translate_tts_result(%{success: false} = result),
    do: {:error, "Text to speech failed: #{inspect(result)}"}

  defp translate_tts_result(other),
    do: {:error, "Unexpected response from text_to_speech: #{inspect(other)}"}
end
