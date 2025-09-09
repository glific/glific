defmodule Glific.ThirdParty.OpenAI.AskmeBot do
  @moduledoc """
  Glific AskMeBot module for all API calls to openAI
  """

  @endpoint "https://api.openai.com/v1"

  @doc """
  Calls the OpenAI response api and fetch the answer for AskMe bot
  """
  @spec askme(map()) :: {:ok, String.t()} | {:error, String.t()}
  def askme(params) do
    Glific.Metrics.increment("askme bot requests")
    api_key = Glific.get_open_ai_key()
    vector_store_id = Application.get_env(:glific, :askme_bot_vector_store_id)
    url = @endpoint <> "/responses"
    input = Map.get(params, "input", [])

    base =
      %{
        "model" => "gpt-4o-mini",
        "input" => input,
        "tools" => [
          %{
            "type" => "file_search",
            "vector_store_ids" => [vector_store_id],
            "max_num_results" => 20
          }
        ]
      }

    middleware = [
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"authorization", "Bearer " <> api_key}]}
    ]

    Tesla.client(middleware)
    |> Tesla.post(url, base, opts: [adapter: [recv_timeout: 120_000]])
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        content = get_in(body, ["output", Access.at(1), "content", Access.at(0), "text"])
        {:ok, content}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Unexpected OpenAI response (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP error calling OpenAI: #{inspect(reason)}"}
    end
  end
end
