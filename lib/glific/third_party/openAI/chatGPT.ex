defmodule Glific.OpenAI.ChatGPT do
  @moduledoc """
  Glific chatGPT module for all API calls to chatGPT
  """

  alias Glific.Partners

  @endpoint "https://api.openai.com/v1/chat/completions"

  @default_params %{
    "model" => "gpt-3.5-turbo-16k",
    "temperature" => 0.7,
    "max_tokens" => 250,
    "top_p" => 1,
    "frequency_penalty" => 0,
    "presence_penalty" => 0
  }

  @doc """

  """
  @spec parse(non_neg_integer(), String.t(), map()) :: tuple()
  def parse(org_id, question_text, params \\ %{}) do
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

    client(org_id)
    |> Tesla.post(@endpoint, data, opts: [adapter: [recv_timeout: 20_000]])
    |> handle_response()
  end

  @spec handle_response(tuple()) :: tuple()
  defp handle_response(response) do
    response
    |> case do
      {:ok, %Tesla.Env{status: 200, body: %{"choices" => []} = body}} ->
        {:error, "Got empty response #{inspect(body)}"}

      {:ok, %Tesla.Env{status: 200, body: %{"choices" => choices} = _body}} ->
        {:ok, hd(choices)["message"]["content"]}

      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:error, "Got different response #{inspect(body)}"}

      {_status, response} ->
        {:error, "invalid response #{inspect(response)}"}
    end
  end

  @doc """
    Get the tesla client with existing configurations.
  """
  @spec client(non_neg_integer()) :: Tesla.Client.t()
  def client(org_id) do
    {:ok, %{api_key: api_key}} = credentials(org_id)

    middleware = [
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"authorization", "Bearer " <> api_key}]}
    ]

    Tesla.client(middleware)
  end

  @spec credentials(non_neg_integer()) :: tuple()
  defp credentials(org_id) do
    organization = Partners.organization(org_id)

    organization.services["open_ai"]
    |> case do
      nil ->
        {:error, "Secret not found."}

      credentials ->
        {:ok, %{api_key: credentials.secrets["api_key"]}}
    end
  end
end
