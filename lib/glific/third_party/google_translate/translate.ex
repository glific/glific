defmodule Glific.GoogleTranslate.Translate do
  @moduledoc """
  Glific Google Translate module for all API calls to Google Translate
  """

  alias Glific.Partners

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
  @spec parse(String.t(), String.t(), map()) :: tuple()
  def parse(api_key, question_text, params \\ %{}) do
    data =
      @default_params
      |> Map.merge(params)
      |> Map.merge(%{
        "messages" => [
          %{
            "role" => "system",
            "content" => question_text
          }
        ]
      })

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
        {:ok, translations |> Enum.map(& &1["translatedText"])}

      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:error, "Unexpected response format: #{inspect(body)}"}

      {_status, response} ->
        {:error, "Invalid response: #{inspect(response)}"}
    end
  end

  @doc """
    Get the API key with existing configurations.
  """
  @spec get_api_key(non_neg_integer()) :: String.t()
  def get_api_key(org_id) do
    {:ok, %{api_key: api_key}} = credentials(org_id)
    api_key
  end

  @spec credentials(non_neg_integer()) :: tuple()
  defp credentials(org_id) do
    organization = Partners.organization(org_id)

    organization.services["google-translate"]
    |> case do
      nil ->
        {:error, "Secret not found."}

      credentials ->
        {:ok, %{api_key: credentials.secrets["api_key"]}}
    end
  end
end
