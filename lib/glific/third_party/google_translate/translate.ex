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

    # Split the text into lines
    lines = String.split(question_text, "\n")

    # Partition the lines into translatable and non-translatable segments
    {translatable_segments, non_translatable_segments} =
      Enum.reduce(lines, {[], []}, fn line, {trans, non_trans} ->
        if String.starts_with?(line, "@") and
             line |> String.trim() |> String.split() |> length() == 1 do
          {trans, [line | non_trans]}
        else
          {[line | trans], non_trans}
        end
      end)

    translatable_text = Enum.reverse(translatable_segments) |> Enum.join("\n")
    non_translatable_segments = Enum.reverse(non_translatable_segments)

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
    |> handle_response(non_translatable_segments)
  end

  @spec handle_response(tuple(), list()) :: tuple()
  defp handle_response(response, non_translatable_segments) do
    response
    |> case do
      {:ok, %Tesla.Env{status: 200, body: %{"data" => %{"translations" => translations}}}} ->
        translated_texts =
          translations
          |> Enum.map(fn translation -> translation["translatedText"] end)
          |> Enum.join("\n")

        # Combine translated and non-translatable segments
        combined_texts =
          non_translatable_segments
          |> Enum.reduce(translated_texts, fn seg, acc ->
            acc <> seg
          end)

        {:ok, combined_texts}

      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:error, "Unexpected response format: #{inspect(body)}"}

      {_status, %Tesla.Env{status: status, body: error}} when status in 400..499 ->
        error_message = get_in(error, ["error", "message"])
        {:error, error_message}

      {_status, response} ->
        {:error, "invalid response #{inspect(response)}"}
    end
  end
end
