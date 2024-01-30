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
    data = %{
      "q" => question_text,
      "source" => languages["source"],
      "target" => languages["target"]
    }

    middleware = [
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [{"Content-Type", "application/json"}, {"X-Goog-Api-Key", api_key}]}
    ]

    middleware
    |> Tesla.client()
    |> Tesla.post(@endpoint, data, opts: [adapter: [recv_timeout: 120_000]])
    |> handle_response()
  end

  @spec handle_response(tuple()) :: tuple()
  defp handle_response(response) do
    response
    |> case do
      {:ok, %Tesla.Env{status: 200, body: %{"data" => %{"translations" => translations}}}} ->
        translated_texts =
          translations
          |> Enum.map(fn translation -> translation["translatedText"] end)

        {:ok, hd(translated_texts)}

      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:error, "Unexpected response format: #{inspect(body)}"}

      {_status, response} ->
        {:error, "Invalid response: #{inspect(response)}"}
    end
  end
end
