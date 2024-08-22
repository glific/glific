defmodule Glific.GoogleTranslate.Translate do
  @moduledoc """
  Glific Google Translate module for all API calls to Google Translate
  """

  @endpoint "https://translation.googleapis.com/language/translate/v2"

  @doc """
  API call to Google Translate.
  """
  @spec parse(String.t(), String.t(), map()) :: tuple()
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

    translatable_text =
      translatable_segments
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
    |> handle_response(non_translatable_segments, translatable_segments)
  end

  @spec handle_response(tuple(), list(), list()) :: tuple()
  defp handle_response(response, non_translatable_segments, translatable_segments) do
    response
    |> case do
      {:ok, %Tesla.Env{status: 200, body: %{"data" => %{"translations" => translations}}}} ->
        translated_texts =
          translations
          |> Enum.map(fn translation -> translation["translatedText"] end)

        translated_lines =
          translated_texts
          |> Enum.flat_map(fn text -> String.split(text, "\n") end)

        translatable_indices =
          translatable_segments
          |> Enum.map(fn {index, _original_text} -> index end)
          |> Enum.reverse()

        translated_lines_with_indices =
          Enum.zip(translatable_indices, translated_lines)

        all_segments =
          (translated_lines_with_indices ++ non_translatable_segments)
          |> Enum.sort_by(fn {index, _text} -> index end)

        combined_texts =
          all_segments
          |> Enum.map_join("\n", fn {_, text} -> text end)

        {:ok, combined_texts}

      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:error, "Unexpected response format: #{inspect(body)}"}

      {_status, %Tesla.Env{status: status, body: error}} when status in 400..499 ->
        error_message = get_in(error, ["error", "message"])
        {:error, error_message}

      {_status, response} ->
        {:error, "Invalid response #{inspect(response)}"}
    end
  end
end
