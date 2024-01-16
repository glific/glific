defmodule Glific.GoogleTranslate.Translate do
  @moduledoc """
  Glific Google Translate module for all API calls to Google Translate
  """

  @endpoint "https://translation.googleapis.com/language/translate/v2"

  @default_params %{
    "temperature" => 0.7,
    "max_tokens" => 250,
    "top_p" => 1,
    "frequency_penalty" => 0,
    "presence_penalty" => 0
  }

  @doc """
  API call to google translate
  """
  def parse(api_key, question_text, source_lang, target_lang, params \\ %{}, format \\ "text") do
    data =
      @default_params
      |> Map.merge(params)
      |> Map.merge(%{
        "q" => question_text,
        "source" => source_lang,
        "target" => target_lang,
        "format" => format
      })

    IO.inspect(data)

    middleware = [
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [{"Content-Type", "application/json"}, {"X-Goog-Api-Key", api_key}]}
    ]

    middleware
    |> Tesla.client()
    |> Tesla.post(@endpoint, data, opts: [adapter: [recv_timeout: 120_000]])
    |> IO.inspect()
    |> handle_response()
  end

  @spec handle_response(tuple()) :: tuple()
  defp handle_response(response) do
    response
    |> case do
      {:ok, %Tesla.Env{status: 200, body: %{"data" => %{"translations" => translations}}}} ->
        {:ok, translations |> Enum.map(& &1["translatedText"])}

      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:error, "Unexpected response format: #{inspect(body)}"}

      {_status, response} ->
        {:error, "Invalid response: #{inspect(response)}"}
    end
  end
end
