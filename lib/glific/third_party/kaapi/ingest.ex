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
    organizations = get_organisations()
    total_orgs = length(organizations)
    Logger.info("Starting sync for #{total_orgs} organizations")

    results =
      organizations
      |> Task.async_stream(
        &sync_organization_assistants/1,
        max_concurrency: 10,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {:error, :timeout}
        {:exit, reason} -> {:error, reason}
      end)

    Logger.info("Completed sync for #{total_orgs} organizations")
    {:ok, results}
  end

  def sync_organization_assistants(%{id: org_id}) do
    Logger.info("Starting sync for organization: #{org_id}")

    result =
      case ingest_assistants(org_id) do
        {:ok, assistant_results} ->
          Logger.info(
            "Successfully synced #{length(assistant_results)} assistants for organization #{org_id}"
          )

          {:ok, assistant_results}

        {:error, reason} ->
          Logger.error("Failed to sync assistants for organization #{org_id}: #{inspect(reason)}")
          {:error, reason}
      end

    {org_id, result}
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
    |> where([o], o.status != "inactive")
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
    assistants =
      Assistant
      |> where([a], a.organization_id == ^organization_id)
      |> Repo.all(organization_id: organization_id)

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
        attrs = %{instructions: "You are a helpful assistant."}

        case Filesearch.update_assistant(assistant.id, attrs) do
          {:ok, updated_assistant} ->
            ApiClient.call_ingest_api(organization_id, updated_assistant.assistant_id)

          {:error, reason} ->
            Logger.error("Failed to update assistant #{assistant.id}: #{inspect(reason)}")
            {:error, "Failed to update assistant"}
        end

      true ->
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
            case check_and_process_assistant(organization_id, assistant) do
              {:ok, result} ->
                Logger.info(
                  "Successfully processed assistant #{assistant.assistant_id} for org #{organization_id}"
                )

                {:ok, result}

              {:error, reason} ->
                Logger.error(
                  "Failed to process assistant #{assistant.assistant_id} for org #{organization_id}: #{inspect(reason)}"
                )

                {:error, reason}
            end
          end)

        {:ok, results}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
