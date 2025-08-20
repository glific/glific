defmodule Glific.ThirdParty.Kaapi.Ingest do
  @moduledoc """
  Handles synchronization of assistants with the Kaapi AI platform.

  Provides functionality to sync assistants across organizations which have Kaapi enabled.
  """
  import Ecto.Query, warn: false

  alias Glific.{
    Filesearch,
    Filesearch.Assistant,
    Partners.Organization,
    Partners.Provider,
    Partners.Credential,
    Repo,
    ThirdParty.Kaapi
  }

  require Logger

  @doc """
  Syncs all assistants for organizations with Kaapi platform enabled.

  Processes organizations concurrently and syncs their assistants.
  Returns summary of success/error counts with detailed logging.

  ## Examples
      iex> sync_assistants()
      {:ok, [{1, {:ok, [{:ok, "Assistant synced successfully"}]}}]}
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

  defp sync_organization_assistants(org_id) do
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

    result
  end

  @spec get_organisations() :: [Organization.t()]
  defp get_organisations do
    query =
      from(o in Organization,
        left_join: p in Provider,
        on: p.shortcode == "kaapi",
        left_join: c in Credential,
        on: c.organization_id == o.id and c.provider_id == p.id,
        where: not is_nil(c.id),
        where: c.is_active == true,
        select: o.id,
        distinct: o.id
      )

    Repo.all(query, skip_organization_id: true)
  end

  @spec fetch_assistants(non_neg_integer) :: {:ok, [Assistant.t()]} | {:error, String.t()}
  defp fetch_assistants(organization_id) do
    Assistant
    |> where([a], a.organization_id == ^organization_id)
    |> Repo.all(organization_id: organization_id)
  end

  @spec check_and_process_assistant(non_neg_integer, Assistant.t()) ::
          {:ok, any()} | {:error, String.t()}
  defp check_and_process_assistant(organization_id, assistant) do
    Repo.put_process_state(organization_id)

    case maybe_set_default_instruction(assistant) do
      {:ok, %{assistant_id: assistant_id}} ->
        Kaapi.ingest_ai_assistant(organization_id, assistant_id)

      {:error, changeset} ->
        {:error, "Failed to update assistant, #{inspect(changeset)}"}
    end
  end

  @spec maybe_set_default_instruction(Assistant.t()) ::
          {:ok, Assistant.t()} | {:error, Ecto.Changeset.t()}
  defp maybe_set_default_instruction(%{instruction: instruction} = assistant)
       when is_binary(instruction) and instruction != "",
       do: {:ok, assistant}

  defp maybe_set_default_instruction(assistant) do
    attrs = %{instructions: "You are a helpful assistant."}
    Filesearch.update_assistant(assistant.id, attrs)
  end

  @spec ingest_assistants(non_neg_integer) :: {:ok, any()} | {:error, String.t()}
  defp ingest_assistants(organization_id) do
    assistants = fetch_assistants(organization_id)

    if assistants == [] do
      Logger.info(
        "KAAPI_ASSISTANTS_EMPTY: No assistants found for organization id: #{organization_id}"
      )
    else
      Logger.info(
        "KAAPI_PROCESSING_START: Starting to process #{length(assistants)} assistants for org: #{organization_id}"
      )
    end

    results =
      assistants
      |> Enum.map(fn assistant ->
        case check_and_process_assistant(organization_id, assistant) do
          {:ok, result} ->
            Logger.info(
              "KAAPI_ASSISTANT_SUCCESS: Successfully processed assistant id: #{assistant.assistant_id} org: #{organization_id}. Response: #{inspect(result)}"
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
  end

  @spec calculate_summary_stats(list()) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  defp calculate_summary_stats(results) do
    Enum.reduce(results, {0, 0, 0}, fn
      {:ok, assistant_results}, {success_orgs, error_orgs, total_assistants} ->
        {success_orgs + 1, error_orgs, total_assistants + length(assistant_results)}

      {:error, _reason}, {success_orgs, error_orgs, total_assistants} ->
        {success_orgs, error_orgs + 1, total_assistants}

      _, acc ->
        acc
    end)
  end
end
