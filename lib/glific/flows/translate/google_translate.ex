defmodule Glific.Flows.Translate.GoogleTranslate do
  @moduledoc """
  Code to translate using google translate as the translation engine.
  """
  @behaviour Glific.Flows.Translate.Translate

  alias Glific.{
    Flows.Translate.Translate,
    Flows.Translate.TranslateLog,
    GoogleTranslate,
    Settings
  }

  @doc """
  Translate a list of strings from language 'src' to language 'dst'.
  Returns either {:ok, [String.t()]} with the translated list in the same order,
  or {:error, String.t()} with an error message.

  ## Examples

      iex> Glific.Flows.Translate.GoogleTranslate.translate(["thank you for joining", "correct answer"], "English", "Hindi")
      {:ok, ["शामिल होने के लिए धन्यवाद", "सही जवाब"]}
  """
  @spec translate([String.t()], String.t(), String.t(), Keyword.t()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def translate(strings, src, dst, opts \\ []) do
    org_id = Keyword.get(opts, :org_id)
    language_code = Settings.get_language_code(org_id)

    src_lang_code = Map.get(language_code, src, src)
    dst_lang_code = Map.get(language_code, dst, dst)

    languages = %{
      "source" => src_lang_code,
      "target" => dst_lang_code,
      "src" => src,
      "dst" => dst
    }

    {texts, errors} =
      strings
      |> Translate.check_large_strings(opts)
      |> Task.async_stream(fn text -> do_translate(text, languages, org_id) end,
        timeout: 300_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce({[], []}, &handle_async_response/2)

    if errors == [] do
      {:ok, texts}
    else
      {:error,
       "Google Translate failed for #{length(errors)} of #{length(texts)} string(s): #{hd(errors)}"}
    end
  end

  # add the translated string into list of string if translated successfully.
  # add the empty string into list of string (without recording an error) if translation
  # timed out, so it can be retried in the next go -- successfully translated strings are
  # updated in the first go and leftovers translated in a second go.
  # a hard API error (not a timeout) also adds "" to keep the list aligned with the input,
  # but is tracked separately so the caller can tell it apart from a genuine empty translation.
  @spec handle_async_response(tuple(), {[String.t()], [String.t()]}) ::
          {[String.t()], [String.t()]}
  defp handle_async_response({:ok, {:ok, translated_text}}, {texts, errors}),
    do: {[translated_text | texts], errors}

  defp handle_async_response({:ok, {:error, reason}}, {texts, errors}),
    do: {["" | texts], [reason | errors]}

  defp handle_async_response({:exit, :timeout}, {texts, errors}), do: {["" | texts], errors}

  @spec do_translate(String.t(), map(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp do_translate(strings, languages, org_id) do
    api_key = Glific.get_google_translate_key()

    GoogleTranslate.Translate.parse(api_key, strings, languages)
    |> case do
      {:ok, result} ->
        %{
          text: strings,
          translated_text: result,
          source_language: languages["src"],
          destination_language: languages["dst"],
          translation_engine: "Google Translate",
          status: true,
          organization_id: org_id
        }
        |> TranslateLog.create_translate_log()

        {:ok, result}

      {:error, error} ->
        %{
          text: strings,
          source_language: languages["src"],
          destination_language: languages["dst"],
          translation_engine: "Google Translate",
          status: false,
          error: error,
          organization_id: org_id
        }
        |> TranslateLog.create_translate_log()

        Glific.log_error(
          "Google Translate failed for org #{org_id} (#{languages["src"]} -> #{languages["dst"]}): #{error}",
          true
        )

        {:error, error}
    end
  end
end
