defmodule Glific.Dify.ApiClient do
  @moduledoc """
  Glific module for API calls to Dify
  """

  use Tesla

  require Logger

  @endpoint "https://api.dify.ai/v1"

  plug(Tesla.Middleware.JSON)

  @doc """
  Send a chat message to Dify and get a response.
  """
  @spec chat_messages(map(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def chat_messages(body, api_key) do
    url = @endpoint <> "/chat-messages"

    post(url, body, headers: headers(api_key), opts: [adapter: [recv_timeout: 120_000]])
    |> parse_response()
  end

  @spec headers(String.t()) :: list()
  defp headers(api_key) do
    [{"authorization", "Bearer " <> api_key}]
  end

  @spec parse_response({:ok, Tesla.Env.t()} | {:error, any()}) ::
          {:ok, map()} | {:error, String.t()}
  defp parse_response({:ok, %{body: body, status: status}})
       when status >= 200 and status < 300 do
    {:ok, body}
  end

  defp parse_response({:ok, %{body: body, status: status}}) do
    Logger.error("Dify API error: #{inspect(body)} with status #{status}")
    {:error, "Dify API error (#{status}): #{inspect(body)}"}
  end

  defp parse_response({:error, reason}) do
    Logger.error("HTTP error calling Dify: #{inspect(reason)}")
    {:error, "HTTP error calling Dify: #{inspect(reason)}"}
  end
end
