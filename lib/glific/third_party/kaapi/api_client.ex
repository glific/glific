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
  @spec onboard_to_kaapi(map()) :: {:ok, %{data: %{api_key: String.t()}}} | {:error, String.t()}
  def onboard_to_kaapi(params) do
    endpoint = kaapi_config(:kaapi_endpoint)
    api_key = kaapi_config(:kaapi_api_key)

    payload = %{
      organization_name: params.organization_name,
      project_name: params.project_name,
      user_name: params.user_name
    }

    payload =
      if params[:openai_api_key] do
        Map.put(payload, :openai_api_key, params[:openai_api_key])
      else
        payload
      end

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
  @spec ingest_ai_assistants(non_neg_integer, String.t()) :: {:ok, any()} | {:error, String.t()}
  def ingest_ai_assistants(org_api_key, assistant_id) do
    endpoint = kaapi_config(:kaapi_endpoint)

    middleware = [
      {Tesla.Middleware.Headers, headers(org_api_key)},
      {Tesla.Middleware.BaseUrl, endpoint}
    ]

    middleware
    |> Tesla.client()
    |> post("api/v1/assistant/#{assistant_id}/ingest", %{})
    |> case do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
        {:ok, %{message: "Assistant synced successfully"}}

      {:ok, %Tesla.Env{status: 409}} ->
        # In this API, 409 cannot be considered as a failure so treating it as a special case
        {:ok, %{message: "Assistant already exists in kaapi"}}

      result ->
        parse_kaapi_response(result)
    end
  end

  # Private
  @spec parse_kaapi_response(Tesla.Env.result()) :: {:ok, map()} | {:error, String.t() | map()}
  defp parse_kaapi_response({:ok, %Tesla.Env{body: %{error: error_msg}}})
       when is_binary(error_msg) do
    {:error, error_msg}
  end

  defp parse_kaapi_response({:ok, %Tesla.Env{status: status, body: body}})
       when status in 200..299 do
    {:ok, body}
  end

  defp parse_kaapi_response({:ok, %Tesla.Env{status: status, body: body}}) do
    {:error, %{status: status, body: body}}
  end

  defp parse_kaapi_response({:error, reason}) do
    {:error, reason}
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
