defmodule Glific.ThirdParty.Kaapi.ApiClient do
  @moduledoc """
  API Client for Kaapi Integration.
  """

  use Tesla
  require Logger

  # client with runtime config (API key / base URL).
  defp client(api_key) do
    base_url = kaapi_config(:kaapi_endpoint)

    Tesla.client([
      {Tesla.Middleware.BaseUrl, base_url},
      {Tesla.Middleware.Headers, headers(api_key)},
      {Tesla.Middleware.JSON, engine_opts: [keys: :atoms]},
      Tesla.Middleware.Telemetry
    ])
  end

  @doc """
  Onboard NGOs to Kaapi
  """
  def onboard_to_kaapi(params) do
    api_key = kaapi_config(:kaapi_api_key)

    body = %{
      organization_name: params.organization_name,
      project_name: params.project_name,
      user_name: params.user_name
    }

    api_key
    |> client()
    |> Tesla.post("/api/v1/onboard", body)
    |> parse_kaapi_response()
  end

  @doc """
  Create an assistant in Kaapi
  """
  @spec create_assistant(map(), binary()) :: {:ok, map()} | {:error, String.t()}
  def create_assistant(body, org_api_key) do
    org_api_key
    |> client()
    |> Tesla.post("/api/v1/assistant", body)
    |> parse_kaapi_response()
  end

  @doc """
  Update an assistant in Kaapi
  """
  @spec update_assistant(binary(), map(), binary()) :: {:ok, map()} | {:error, String.t()}
  def update_assistant(assistant_id, body, org_api_key) do
    org_api_key
    |> client()
    |> Tesla.patch("/api/v1/assistant/#{assistant_id}", body)
    |> parse_kaapi_response()
  end

  @spec parse_kaapi_response(Tesla.Env.result()) ::
          {:ok, %{api_key: String.t()}} | {:error, String.t()}
  defp parse_kaapi_response({:ok, %Tesla.Env{status: status, body: %{api_key: api_key}}})
       when status in 200..299 and is_binary(api_key) do
    {:ok, %{api_key: api_key}}
  end

  defp parse_kaapi_response({:ok, %Tesla.Env{status: status, body: %{error: msg}}})
       when is_binary(msg) do
    Logger.error("KAAPI API error (status=#{status}): #{inspect(msg)}")
    {:error, msg}
  end

  defp parse_kaapi_response({:ok, %Tesla.Env{status: status, body: body}})
       when status >= 400 do
    msg =
      case body do
        %{error: e} when is_binary(e) -> e
        _ -> "HTTP #{status}"
      end

    Logger.error("KAAPI API HTTP error (status=#{status}): #{inspect(msg)}")
    {:error, msg}
  end

  defp parse_kaapi_response({:error, reason}) do
    Logger.error("KAAPI API transport error: #{inspect(reason)}")
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
