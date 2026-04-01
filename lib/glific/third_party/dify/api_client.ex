defmodule Glific.Dify.ApiClient do
  @moduledoc """
  Glific module for API calls to Dify
  """

  require Logger

  @endpoint "https://api.dify.ai/v1"

  @doc """
  Send a chat message to Dify and get a response.
  """
  @spec chat_messages(map(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def chat_messages(body, api_key) do
    Req.post(
      base_url: @endpoint,
      url: "/chat-messages",
      json: body,
      headers: headers(api_key),
      receive_timeout: 60_000
    )
    |> parse_response()
  end

  @spec headers(String.t()) :: list()
  defp headers(api_key) do
    [authorization: "Bearer " <> api_key]
  end

  @spec parse_response({:ok, Req.Response.t()} | {:error, any()}) ::
          {:ok, map()} | {:error, String.t()}
  defp parse_response({:ok, %Req.Response{status: status, body: body}})
       when status >= 200 and status < 300 do
    {:ok, body}
  end

  defp parse_response({:ok, %Req.Response{status: status, body: body}}) do
    Logger.error("Dify API error: #{inspect(body)} with status #{status}")
    {:error, "Dify API error (#{status}): #{inspect(body)}"}
  end

  defp parse_response({:error, reason}) do
    Logger.error("HTTP error calling Dify: #{inspect(reason)}")
    {:error, "HTTP error calling Dify: #{inspect(reason)}"}
  end
end
