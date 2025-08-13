defmodule Glific.Providers.Kaapi do
  alias Glific.{Filesearch.Assistant, Organizations, Partners}
  require Logger
  use Tesla
  # Glific.Providers.Kaapi.sync_assistants(1)
  def sync_assistants(organisation_id) do
    ingest_assistants(organisation_id)
  end

  defp get_kaapi_api_key(organization_id) do
    organization = Partners.organization(organization_id)
    kaapi_credentials = organization.services["kaapi"]
    kaapi_credentials.secrets["api_key"]
  end

  defp fetch_assistansts(organization_id) do
    assistants = Assistant.list_assistants(%{organization_id: organization_id})
    {:ok, assistants}
  end

  defp get_kaapi_ingest_url(assistant_id) do
    Application.get_env(:glific, :kaapi_endpoint) <> "api/v1/assistant/#{assistant_id}/ingest"
  end

  defp ingest_assistants(organization_id) do
    {:ok, assistants} = fetch_assistansts(organization_id)

    assistants
    |> Enum.each(fn assistant ->
      call_ingest_api(organization_id, assistant.assistant_id)
    end)
  end

  defp call_ingest_api(organization_id, assistant_id) do
    IO.inspect(get_kaapi_ingest_url(assistant_id), label: "Ingest URL")
    IO.inspect(headers(organization_id))

    post(
      get_kaapi_ingest_url(assistant_id),
      "",
      headers(organization_id)
    )
    |> parse_response()
  end

  defp headers(organization_id) do
    kaapi_api_key = get_kaapi_api_key(organization_id)

    [
      {"X-API-KEY", "ApiKey #{kaapi_api_key}"},
      {"accept", "application/json"}
    ]
  end

  defp parse_response({:ok, %{body: resp_body, status: status}})
       when status >= 200 and status < 300 do
    {:ok, resp_body}
  end

  defp parse_response({:ok, %{body: resp_body, status: status}}) do
    Logger.error("API request failed with status: #{status}, body: #{inspect(resp_body)}")
    {:error, "Request failed with status #{status}"}
  end

  defp parse_response({:error, reason}) do
    Logger.error("API request error: #{inspect(reason)}")
    {:error, reason}
  end

  defp parse_response(response) do
    Logger.error("Unexpected response format: #{inspect(response)}")
    {:error, "Unexpected response format"}
  end
end
