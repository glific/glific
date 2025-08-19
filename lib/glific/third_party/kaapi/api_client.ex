defmodule Glific.ThirdParty.Kaapi.ApiClient do
  @moduledoc """
  Glific module for API calls to kaapi
  """

  alias Glific.Partners

  use Tesla
  require Logger

  @kaapi_endpoint Application.compile_env(:glific, :kaapi_endpoint)

  @doc """
    Ingests an assistant into the Kaapi platform.
  """

  @spec call_ingest_api(non_neg_integer, String.t()) :: {:ok, any()} | {:error, String.t()}
  def call_ingest_api(organization_id, assistant_id) do
    post(
      get_kaapi_ingest_url(assistant_id),
      "",
      headers: headers(organization_id)
    )
    |> parse_response()
  end

  @spec get_kaapi_ingest_url(String.t()) :: String.t()
  defp get_kaapi_ingest_url(assistant_id) do
    @kaapi_endpoint <> "api/v1/assistant/#{assistant_id}/ingest"
  end

  @spec get_kaapi_api_key(non_neg_integer) :: {:ok, String.t()} | {:error, String.t()}
  defp get_kaapi_api_key(organization_id) do
    organization = Partners.organization(organization_id)
    kaapi_credentials = organization.services["kaapi"]
    kaapi_credentials.secrets["api_key"]
  end

  @spec headers(non_neg_integer) :: [{String.t(), String.t()}]
  defp headers(organization_id) do
    kaapi_api_key = get_kaapi_api_key(organization_id)

    [
      {"X-API-KEY", "ApiKey #{kaapi_api_key}"},
      {"accept", "application/json"}
    ]
  end

  @spec parse_response(Tesla.Env.result()) :: {:ok, any()} | {:error, String.t()}
  defp parse_response({:ok, %{status: status}})
       when status >= 200 and status < 300 do
    {:ok, "Assistant synced successfully"}
  end

  defp parse_response({:ok, %{status: 409}}) do
    {:ok, "Assistant already exists in kaapi"}
  end

  defp parse_response({:ok, %{body: resp_body, status: status}}) do
    {:error, "Request failed with status #{status}. #{inspect(resp_body)}"}
  end

  defp parse_response({:error, reason}) do
    {:error, reason}
  end
end
