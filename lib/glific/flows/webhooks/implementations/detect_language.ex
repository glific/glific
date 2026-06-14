defmodule Glific.Flows.Webhooks.DetectLanguage do
  @moduledoc """
  Detect the spoken language in an audio file using the Bhashini language-detection
  service.

  Accepts a `speech` field containing an HTTPS URL to an audio file, sends it to
  the Bhashini audio-language-detection endpoint, and returns the ISO language
  label on success.

  Returns `{:ok, %{detected_language: label}}` on success, or
  `{:error, String.t()}` when the speech field is missing or the Bhashini
  service returns a failure response. The dispatcher encodes those tuples for
  the flow engine via `Glific.Flows.Webhooks.ResultTranslator`.

  Migrated from `Glific.Clients.CommonWebhook.webhook("detect_language", ...)`.
  """

  use Glific.Flows.Webhooks.Sync, name: "detect_language"

  alias Glific.ASR.Bhasini

  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) ::
          {:ok, map()} | {:error, String.t()}
  def call(fields, _ctx) do
    speech = (fields["speech"] || "") |> to_string() |> String.trim()

    if speech == "" do
      {:error, "Missing speech field"}
    else
      detect(speech)
    end
  end

  @spec detect(String.t()) :: {:ok, map()} | {:error, String.t()}
  defp detect(url) do
    case Bhasini.detect_language(url) do
      %{success: true, detected_language: language} ->
        {:ok, %{detected_language: language}}

      %{success: false, detected_language: message} ->
        {:error, message}
    end
  end
end
