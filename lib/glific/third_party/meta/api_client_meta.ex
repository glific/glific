defmodule Glific.ThirdParty.Meta.ApiClientMeta do
  @moduledoc """
  API Client for Meta API Integration.
  """

  require Logger
  use Tesla

  @meta_api_url "https://graph.facebook.com"

  # client with runtime config (API key / base URL).

  defp client() do
    Glific.Metrics.increment("Meta Requests")
    # api_key_for_meta = Glific.get_meta_keys()
    api_key_for_meta =
      Tesla.client([
        {Tesla.Middleware.BaseUrl, @meta_api_url},
        {Tesla.Middleware.Headers, headers(api_key_for_meta)},
        {Tesla.Middleware.JSON, engine_opts: [keys: :atoms]},
        Tesla.Middleware.Telemetry
      ])
  end

  @doc """
  Publish a WhatsApp Flow form to Meta Graph API
  """
  @spec publish_wa_form(String.t()) :: {:ok, map()} | {:error, String.t()}
  def publish_wa_form(flow_id) do
    path = "/#{flow_id}/publish"

    a =
      client()
      |> Tesla.post(path)
      |> parse_response()

    IO.inspect(a, "Data")
  end

  @spec parse_response(Tesla.Env.result()) :: {:ok, map()} | {:error, String.t()}
  defp parse_response({:ok, %Tesla.Env{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp parse_response({:ok, %Tesla.Env{status: status, body: body}}) do
    # error_message = extract_error_message(body)
    Logger.error("Meta API error: #{inspect(body)}")
    {:error, "Meta API error (#{status}): #{body}"}
  end

  defp parse_response({:error, reason}) do
    Logger.error("Meta API request failed: #{inspect(reason)}")
    {:error, "Meta API request failed: #{inspect(reason)}"}
  end

  # @spec extract_error_message(map()) :: String.t()
  # defp extract_error_message(%{message: message}), do: message
  # defp extract_error_message(body), do: inspect(body)

  defp headers(api_key) do
    [
      {"META-API-KEY", api_key},
      {"content-type", "application/json"}
    ]
  end
end
