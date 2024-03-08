defmodule Glific.Flows.Translate.GoogleTranslate do
  @moduledoc """
  Code to translate using google translate as the translation engine.
  """
  @behaviour Glific.Flows.Translate.Translate

  alias Glific.{
    Flows.Translate.Translate,
    Settings
  }

  require Logger

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
    Settings.get_language_code(org_id)
    language_code = Settings.get_language_code(org_id)

    src_lang_code = Map.get(language_code, src, src)
    dst_lang_code = Map.get(language_code, dst, dst)

    languages = %{"source" => src_lang_code, "target" => dst_lang_code}

    strings
    |> Translate.check_large_strings()
    |> Task.async_stream(fn text -> do_translate(text, languages) end,
      timeout: 300_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce([], fn response, acc ->
      handle_async_response(response, acc)
    end)
    |> then(&{:ok, &1})
  end

  # add the translated string into list of string if translated successfully
  # add the empty string into list of string if translation timed out so it can be translated in next go
  # This way successfully translated string will be updated in first go and leftover will be translated in second go
  @spec handle_async_response(tuple(), [String.t()]) :: [String.t()]
  defp handle_async_response({:ok, translated_text}, acc), do: [translated_text | acc]
  defp handle_async_response({:exit, :timeout}, acc), do: ["" | acc]

  @spec do_translate(String.t(), map()) :: String.t() | {:error, String.t()}
  defp do_translate(strings, languages) do
    api_key = Glific.get_google_translate_key()

    Glific.GoogleTranslate.Translate.parse(api_key, strings, languages)
    |> case do
      {:ok, result} ->
        result

      {:error, error} ->
        Logger.error("Error translating: #{error} String: #{strings}")
        ""
    end
  end
end
