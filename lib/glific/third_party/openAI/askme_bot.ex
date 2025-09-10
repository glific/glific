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
        "input" => input,
        "model" => "gpt-5",
        "prompt" => %{
          "id" => "pmpt_68c13895b8748190ac0af72d6747523f0ae6e206c3370b30",
        }
      }

    middleware = [
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"authorization", "Bearer " <> api_key}]}
    ]

    Tesla.client(middleware)
    |> Tesla.post(url, base, opts: [adapter: [recv_timeout: 120_000]])
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        content =
          body
          |> get_in(["output"])
          |> Enum.find_value(fn output ->
            get_in(output, ["content", Access.at(0), "text"])
          end)

        {:ok, content}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Unexpected OpenAI response (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP error calling OpenAI: #{inspect(reason)}"}
    end
  end
end
