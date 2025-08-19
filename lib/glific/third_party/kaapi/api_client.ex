defmodule Glific.ThirdParty.Kaapi.ApiClient do
  @moduledoc """
  API Client for Kaapi Integration.
  """
  use Tesla
  require Logger

  plug(Tesla.Middleware.Telemetry)

  @doc """
  Onboard NGOs to kaapi
  """
  @spec onboard_to_kaapi(map()) :: {:ok, %{api_key: String.t()}} | {:error, String.t()}
  def onboard_to_kaapi(params) do
    endpoint = kaapi_config(:kaapi_endpoint)
    api_key = kaapi_config(:kaapi_api_key)

    payload = %{
      organization_name: params.organization_name,
      project_name: params.project_name,
      user_name: params.user_name
    }

    middleware = [
      {Tesla.Middleware.Headers, headers(api_key)},
      {Tesla.Middleware.BaseUrl, endpoint},
      {Tesla.Middleware.JSON, engine_opts: [keys: :atoms]}
    ]

    middleware
    |> Tesla.client()
    |> Tesla.post("/api/v1/onboard", payload)
    |> parse_kaapi_response()
  end

  @spec parse_kaapi_response(Tesla.Env.result()) ::
          {:ok, %{api_key: String.t()}} | {:error, String.t()}
  defp parse_kaapi_response({:ok, %Tesla.Env{status: status, body: %{api_key: api_key}}})
       when status in 200..299 and is_binary(api_key) do
    {:ok, %{api_key: api_key}}
  end

  defp parse_kaapi_response({:ok, %Tesla.Env{body: %{error: error_msg}}})
       when is_binary(error_msg) do
    Logger.error("KAAPI API error: #{inspect(error_msg)}")
    {:error, error_msg}
  end

  defp parse_kaapi_response({:ok, %Tesla.Env{status: status, body: body}})
       when status >= 400 do
    msg =
      case body do
        %{error: e} when is_binary(e) -> e
        _ -> "HTTP #{status}"
      end

    Logger.error("KAAPI API HTTP error: #{inspect(msg)}")
    {:error, msg}
  end

  defp parse_kaapi_response({:error, message}) do
    Logger.error("KAAPI API transport error: #{inspect(message)}")
    {:error, "API request failed"}
  end

  defp kaapi_config, do: Application.fetch_env!(:glific, __MODULE__)
  defp kaapi_config(key), do: kaapi_config()[key]

  defp headers(api_key) do
    [
      {"X-API-KEY", api_key},
      {"content-type", "application/json"}
    ]
  end
end
