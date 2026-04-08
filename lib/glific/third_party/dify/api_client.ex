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
    [
      base_url: @endpoint,
      url: "/chat-messages",
      json: body,
      headers: headers(api_key),
      receive_timeout: 60_000
    ]
    |> maybe_add_plug()
    |> Req.post()
    |> parse_response()
  end

  @spec headers(String.t()) :: list()
  defp headers(api_key) do
    [authorization: "Bearer " <> api_key]
  end

  defp maybe_add_plug(opts) do
    if plug = Application.get_env(:glific, :dify_req_plug) do
      Keyword.put(opts, :plug, plug)
    else
      opts
    end
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
