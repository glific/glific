defmodule Glific.GoogleTranslate.Translate do
  @moduledoc """
  Glific Google Translate module for all API calls to Google Translate
  """

  @endpoint "https://translation.googleapis.com/language/translate/v2"

  @doc """
  API call to Google Translate.
  """
  @spec parse(String.t(), String.t(), map()) :: {:ok, any()} | {:error, any()}
  def parse(api_key, question_text, languages) do
    lines = String.split(question_text, "\n")

    indexed_lines = Enum.with_index(lines)

    {translatable_segments, non_translatable_segments} =
      Enum.reduce(indexed_lines, {[], []}, fn {line, index}, {trans, non_trans} ->
        if String.starts_with?(line, "@") and
             line |> String.trim() |> String.split() |> length() == 1 do
          {trans, [{index, line} | non_trans]}
        else
          {[{index, line} | trans], non_trans}
        end
      end)

    all_segments_map =
      (translatable_segments ++ non_translatable_segments)
      |> Enum.sort_by(fn {index, _line} -> index end)
      |> Enum.into(%{})

    translatable_text =
      all_segments_map
      |> Enum.sort_by(fn {index, _line} -> index end)
      |> Enum.map_join("\n", fn {_index, line} -> line end)

    data = %{
      "q" => translatable_text,
      "source" => languages["source"],
      "target" => languages["target"],
      "format" => "text"
    }

    middleware = [
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [{"Content-Type", "application/json"}, {"X-Goog-Api-Key", api_key}]}
    ]

    middleware
    |> Tesla.client()
    |> Tesla.post(@endpoint, data, opts: [adapter: [recv_timeout: 120_000]])
    |> handle_response(non_translatable_segments, all_segments_map)
  end

  @spec handle_response(tuple(), list(), map()) :: {:ok, any} | {:error, any}
  defp handle_response(response, non_translatable_segments, all_segments_map) do
    with {:ok, translations} <- extract_translations(response),
         translated_segments_with_indices <-
           map_translations_to_indices(translations, all_segments_map),
         final_segments <-
           replace_non_translatable_segments(
             translated_segments_with_indices,
             non_translatable_segments,
             all_segments_map
           ),
         combined_texts <- combine_segments(final_segments) do
      {:ok, combined_texts}
    else
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:error, "Unexpected response format: #{inspect(body)}"}

      {_status, %Tesla.Env{status: status, body: error}} when status in 400..499 ->
        error_message = get_in(error, ["error", "message"])
        {:error, error_message}

      {_status, response} ->
        {:error, "Invalid response #{inspect(response)}"}
    end
  end

  @spec extract_translations(tuple()) ::
          {:ok, list(String.t())} | {:error, String.t()}
  defp extract_translations(
         {:ok, %Tesla.Env{status: 200, body: %{"data" => %{"translations" => translations}}}}
       ) do
    translated_texts =
      translations
      |> Enum.map(& &1["translatedText"])
      |> Enum.flat_map(&String.split(&1, "\n"))

    {:ok, translated_texts}
  end

  defp extract_translations(_unexpected) do
    {:error, "Failed to extract translations"}
  end

  @spec map_translations_to_indices(list(String.t()), map()) :: list()
  defp map_translations_to_indices(translated_texts, all_segments_map) do
    Enum.zip(Map.keys(all_segments_map), translated_texts)
  end

  @spec replace_non_translatable_segments(
          list(),
          list(),
          map()
        ) :: list()
  defp replace_non_translatable_segments(
         translated_segments_with_indices,
         non_translatable_segments,
         all_segments_map
       ) do
    translated_segments_with_indices
    |> Enum.map(fn {index, translated_text} ->
      if Enum.any?(non_translatable_segments, fn {non_trans_index, _} ->
           non_trans_index == index
         end) do
        {index, all_segments_map[index]}
      else
        {index, translated_text}
      end
    end)
    |> Enum.sort_by(fn {index, _text} -> index end)
  end

  @spec combine_segments(list({integer(), String.t()})) :: String.t()
  defp combine_segments(final_segments) do
    final_segments
    |> Enum.map_join("\n", fn {_, text} -> text end)
  end
end
