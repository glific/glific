defmodule Glific.ThirdParty.Kaapi.ApiClient do
  @moduledoc """
  API Client for Kaapi Integration.
  """

  use Tesla
  require Logger

  plug(Tesla.Middleware.JSON, engine_opts: [keys: :atoms])
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
      {Tesla.Middleware.BaseUrl, endpoint}
    ]

    middleware
    |> Tesla.client()
    |> post("/api/v1/onboard", payload)
    |> parse_kaapi_response()
  end

  @doc """
  Ingests an assistant into the Kaapi platform.
  """
  @spec call_ingest_api(non_neg_integer, String.t()) :: {:ok, any()} | {:error, String.t()}
  def call_ingest_api(org_api_key, assistant_id) do
    endpoint = kaapi_config(:kaapi_endpoint)

    middleware = [
      {Tesla.Middleware.Headers, headers(org_api_key)},
      {Tesla.Middleware.BaseUrl, endpoint}
    ]

    middleware
    |> Tesla.client()
    |> post("api/v1/assistant/#{assistant_id}/ingest")
    |> case do
      {:ok, %Tesla.Env{status: 409}} ->
        # In this API, 409 cannot be considered as a failure so treating it as a special case
        {:ok, %{message: "Assistant already exists in kaapi"}}

      result ->
        parse_kaapi_response(result)
    end
  end

  # Private
  @spec parse_kaapi_response(Tesla.Env.result()) :: {:ok, map()} | {:error, String.t()}
  defp parse_kaapi_response({:ok, %Tesla.Env{body: %{error: error_msg}}})
       when is_binary(error_msg) do
    Logger.error("KAAPI API error: #{inspect(error_msg)}")
    {:error, error_msg}
  end

  defp parse_kaapi_response({:ok, %Tesla.Env{status: status, body: body}})
       when status in 200..299 do
    {:ok, body}
  end

  defp parse_kaapi_response({:ok, %Tesla.Env{status: status, body: body}})
       when status >= 400 do
    Logger.error("KAAPI API HTTP error with status #{status}, reason: #{inspect(body)}")
    {:error, "API request failed"}
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
