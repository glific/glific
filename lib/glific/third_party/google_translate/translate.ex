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
    IO.inspect(question_text)
    #contact variables are non_translatable
    {translatable_segments, non_translatable_segments} =
      question_text
      |> String.split("\n")
      |> Enum.split_with(&(!String.starts_with?(&1, "@results")))

    translatable_text = Enum.join(translatable_segments, "\n")

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
    |> IO.inspect()
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
