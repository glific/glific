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
    api_key = Glific.get_open_ai_key()
    url = @endpoint <> "/responses"
    model = Map.get(params, :model, "gpt-4o-mini")

    input = Map.get(params, "input", [])

    base = %{
      "model" => model,
      "input" => input,
      "tools" => [
        %{
          "type" => "file_search",
          "vector_store_ids" => ["vs_Fx8ChbH6bkkFeNlLRdLXyOf4"],
          "max_num_results" => 20,
        },
      ],
    }
IO.inspect(params, label: "base")
    middleware = [
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"authorization", "Bearer " <> api_key}]}
    ]

    Tesla.client(middleware)
    |> Tesla.post(url, base, opts: [adapter: [recv_timeout: 120_000]])
    |> IO.inspect()
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        content = get_in(body, ["output", Access.at(1), "content", Access.at(0), "text"])
        {:ok, content}

      {:ok, %Tesla.Env{status: status, body: body}} when status in 400..499 ->
        {:error, get_in(body, ["error", "message"]) || "OpenAI client error (#{status})"}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Unexpected OpenAI response (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP error calling OpenAI: #{inspect(reason)}"}
    end
  end
end
