defmodule Glific.Providers.Kaapi do
  @moduledoc """
  Provider module for integrating with Kaapi AI platform.
  """

  alias Glific.{Filesearch, Filesearch.Assistant, Partners}
  require Logger
  use Tesla

  @doc """
  Syncs all assistants for an organization with the Kaapi platform.

  ## Examples
      iex> Glific.Providers.Kaapi.sync_assistants(1)
      {:ok, [ok: "Assistant synced successfully"]}

      iex> Glific.Providers.Kaapi.sync_assistants(999)
      {:error, "Organization not found"}
  """
  @spec sync_assistants(non_neg_integer) :: {:ok, any()}
  def sync_assistants(organisation_id) do
    ingest_assistants(organisation_id)
  end

  @spec get_kaapi_ingest_url(String.t()) :: String.t()
  defp get_kaapi_ingest_url(assistant_id) do
    Application.get_env(:glific, :kaapi_endpoint) <> "api/v1/assistant/#{assistant_id}/ingest"
  end

  @spec get_kaapi_api_key(non_neg_integer) :: String.t()
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

  @spec has_valid_instruction?(Assistant.t()) :: boolean()
  defp has_valid_instruction?(assistant) do
    case Map.get(assistant, :instructions) || Map.get(assistant, "instructions") do
      nil -> false
      "" -> false
      instruction when is_binary(instruction) -> true
      _ -> false
    end
  end

  @spec fetch_assistansts(non_neg_integer) :: {:ok, [Assistant.t()]}
  defp fetch_assistansts(organization_id) do
    assistants = Assistant.list_assistants(%{organization_id: organization_id})

    case assistants do
      [] ->
        Logger.info("No assistants found for organization #{organization_id}")
        {:ok, []}

      assistants when is_list(assistants) ->
        {:ok, assistants}
    end
  end

  @spec check_and_process_assistant(non_neg_integer, Assistant.t()) ::
          {:ok, any()} | {:error, String.t()}
  defp check_and_process_assistant(organization_id, assistant) do

    # if no instructions are present, set default instructions
    case has_valid_instruction?(assistant) do
      false ->
        attrs = %{instructions: "Default instructions"}

        case Filesearch.update_assistant(assistant.id, attrs) do
          {:ok, updated_assistant} ->
            call_ingest_api(organization_id, updated_assistant.assistant_id)

          {:error, _} ->
            {:error, "Failed to update assistant"}
        end

      _ ->
        call_ingest_api(organization_id, assistant.assistant_id)
    end
  end

  @spec ingest_assistants(non_neg_integer) :: {:ok, any()}
  defp ingest_assistants(organization_id) do
    case fetch_assistansts(organization_id) do
      {:ok, assistants} ->
        results =
          assistants
          |> Enum.map(fn assistant ->
            check_and_process_assistant(organization_id, assistant)
          end)

        {:ok, results}
    end
  end

  @spec call_ingest_api(non_neg_integer, String.t()) :: {:ok, any()} | {:error, String.t()}
  defp call_ingest_api(organization_id, assistant_id) do
    post(
      get_kaapi_ingest_url(assistant_id),
      "",
      headers: headers(organization_id)
    )
    |> parse_response()
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

  defp parse_response(response) do
    {:error, "Unexpected response format #{inspect(response)}"}
  end
end
