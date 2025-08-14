defmodule Glific.ThirdParty.Kaapi.Ingest do
  @moduledoc """
  Provider module for integrating with Kaapi AI platform.
  """
  import Ecto.Query, warn: false

  alias Glific.{
    Filesearch,
    Filesearch.Assistant,
    Partners,
    Partners.Organization,
    Repo,
    ThirdParty.Kaapi.ApiClient
  }

  require Logger

  @doc """
  Syncs all assistants for an organization with the Kaapi platform.

  ## Examples
      iex> Glific.ThirdParty.Kaapi.Ingest.sync_assistants()
      {:ok, [ok: "Assistant synced successfully"]}

      iex> Glific.Providers.Kaapi.sync_assistants(999)
      {:error, "Organization not found"}
  """

  @spec sync_assistants() :: [{non_neg_integer, {:ok, any()}}]
  def sync_assistants do
    get_organisations()
    |> Enum.map(fn org ->
      Logger.info("Syncing for organization: #{org.id}")

      {:ok, results} = ingest_assistants(org.id)

      Logger.info("synced for organization #{org.id}")

      {org.id, {:ok, results}}
    end)
  end

  @spec has_kaapi_enabled?(non_neg_integer) :: boolean()
  defp has_kaapi_enabled?(organization_id) do
    case Partners.organization(organization_id) do
      %{services: services} when is_map(services) ->
        case services do
          %{"kaapi" => _} -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  @spec get_organisations() :: [Organization.t()]
  defp get_organisations do
    Organization
    |> where([o], o.is_active == true)
    |> Repo.all(skip_organization_id: true)
    |> Enum.filter(fn org ->
      has_kaapi_enabled?(org.id)
    end)
    |> Enum.reject(&is_nil/1)
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
            ApiClient.call_ingest_api(organization_id, updated_assistant.assistant_id)

          {:error, _} ->
            {:error, "Failed to update assistant"}
        end

      _ ->
        ApiClient.call_ingest_api(organization_id, assistant.assistant_id)
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
end
