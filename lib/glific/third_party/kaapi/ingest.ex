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

    Logger.info(
      "KAAPI_SYNC_START: Starting sync for #{total_orgs} organizations with Kaapi enabled"
    )

    results =
      organizations
      |> Task.async_stream(
        &sync_organization_assistants/1,
        max_concurrency: 10,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} ->
          result

        {:exit, :timeout} ->
          Logger.error("KAAPI_SYNC_TIMEOUT: Organization sync timed out after 60 seconds")
          {:error, :timeout}

        {:exit, reason} ->
          Logger.error(
            "KAAPI_SYNC_EXIT: Organization sync exited with reason: #{inspect(reason)}"
          )

          {:error, reason}
      end)

    {success_count, error_count, total_assistants} = calculate_summary_stats(results)

    Logger.info(
      "KAAPI_SYNC_COMPLETE: Completed sync for #{total_orgs} organizations. Success: #{success_count} orgs, Errors: #{error_count} orgs, Total assistants processed: #{total_assistants}"
    )

    {:ok, results}
  end

  def sync_organization_assistants(%{id: org_id}) do
    Logger.info("KAAPI_ORG_START: Starting sync for organization id: #{org_id}")

    result =
      case ingest_assistants(org_id) do
        {:ok, assistant_results} ->
          success_count = Enum.count(assistant_results, fn {status, _} -> status == :ok end)
          error_count = Enum.count(assistant_results, fn {status, _} -> status == :error end)

          Logger.info(
            "KAAPI_ORG_SUCCESS: Organization id: #{org_id} sync completed in. Assistants - Success: #{success_count}, Errors: #{error_count}, Total: #{length(assistant_results)}"
          )

          {:ok, assistant_results}

        {:error, reason} ->
          Logger.error(
            "KAAPI_ORG_ERROR: Organization id: #{org_id} sync failed. Reason: #{inspect(reason)}"
          )

          {:error, reason}
      end

    {org_id, result}
  end

  @spec has_kaapi_enabled?(non_neg_integer) :: boolean()
  defp has_kaapi_enabled?(organization_id) do
    with %{services: services} when is_map(services) <- Partners.organization(organization_id),
         %{"kaapi" => _} <- services do
      true
    else
      _ -> false
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
    case Map.get(assistant, :instructions) do
      nil -> false
      "" -> false
      instruction when is_binary(instruction) -> true
      _ -> false
    end
  end

  @spec fetch_assistansts(non_neg_integer) :: {:ok, [Assistant.t()]} | {:error, String.t()}
  defp fetch_assistansts(organization_id) do
    assistants =
      Assistant
      |> where([a], a.organization_id == ^organization_id)
      |> Repo.all(organization_id: organization_id)

    case assistants do
      [] ->
        Logger.info(
          "KAAPI_ASSISTANTS_EMPTY: No assistants found for organization id: #{organization_id}"
        )

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
            Logger.info(
              "KAAPI_ASSISTANT_UPDATED: Successfully updated assistant id: #{assistant.assistant_id} org: #{organization_id} with default instructions."
            )

            ApiClient.call_ingest_api(organization_id, updated_assistant.assistant_id)

          {:error, reason} ->
            Logger.error(
              "KAAPI_ASSISTANT_UPDATE_ERROR: Failed to update assistant id: #{assistant.assistant_id} org: #{organization_id}. Reason: #{inspect(reason)}"
            )

            {:error, "Failed to update assistant"}
        end

      true ->
        ApiClient.call_ingest_api(organization_id, assistant.assistant_id)
    end
  end

  @spec ingest_assistants(non_neg_integer) :: {:ok, any()} | {:error, String.t()}
  defp ingest_assistants(organization_id) do
    case fetch_assistansts(organization_id) do
      {:ok, assistants} ->
        Logger.info(
          "KAAPI_PROCESSING_START: Starting to process #{length(assistants)} assistants for org: #{organization_id}"
        )

        results =
          assistants
          |> Enum.map(fn assistant ->
            case check_and_process_assistant(organization_id, assistant) do
              {:ok, result} ->
                Logger.info(
                  "KAAPI_ASSISTANT_SUCCESS: Successfully processed assistant id: #{assistant.assistant_id} org: #{organization_id}. Response: #{result}"
                )

                {:ok, result}

              {:error, reason} ->
                Logger.error(
                  "KAAPI_ASSISTANT_ERROR: Failed to process assistant id: #{assistant.assistant_id}  org: #{organization_id}. Reason: #{inspect(reason)}"
                )

                {:error, reason}
            end
          end)

        success_count = Enum.count(results, fn {status, _} -> status == :ok end)
        error_count = Enum.count(results, fn {status, _} -> status == :error end)

        Logger.info(
          "KAAPI_PROCESSING_COMPLETE: Completed processing assistants for org: #{organization_id}. Success: #{success_count}, Errors: #{error_count}, Total: #{length(results)}"
        )

        {:ok, results}

      {:error, reason} ->
        Logger.error(
          "KAAPI_FETCH_ERROR: Failed to fetch assistants for org: #{organization_id}. Reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  # Helper function to calculate summary statistics
  @spec calculate_summary_stats(list()) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  defp calculate_summary_stats(results) do
    Enum.reduce(results, {0, 0, 0}, fn
      {_org_id, {:ok, assistant_results}}, {success_orgs, error_orgs, total_assistants} ->
        {success_orgs + 1, error_orgs, total_assistants + length(assistant_results)}

      {_org_id, {:error, _reason}}, {success_orgs, error_orgs, total_assistants} ->
        {success_orgs, error_orgs + 1, total_assistants}

      _, acc ->
        acc
    end)
  end
end
