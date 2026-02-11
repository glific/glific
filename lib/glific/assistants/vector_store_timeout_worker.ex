defmodule Glific.Assistants.VectorStoreTimeoutWorker do
  @moduledoc """
  Worker for handling async vector store creation timeouts.
  """

  import Ecto.Query
  require Logger

  alias Glific.{
    Assistants.AssistantConfigVersion,
    Assistants.KnowledgeBaseVersion,
    Notifications,
    Repo
  }

  @timeout_hours 1
  @failure_reason "Vector store creation timed out after #{@timeout_hours} hour(s)"

  @doc """
  Periodically checks for in-progress KnowledgeBaseVersions that have exceeded the timeout threshold and marks them as failed.
  """
  @spec process_timeouts(non_neg_integer()) :: :ok
  def process_timeouts(org_id) do
    find_timed_out_versions(org_id)
    |> Enum.each(fn kbv ->
      try do
        mark_as_failed(kbv)
      rescue
        e ->
          Logger.error(
            "Failed to process timeout for KnowledgeBaseVersion #{kbv.id}: #{Exception.message(e)}"
          )
      end
    end)

    :ok
  end

  @spec find_timed_out_versions(non_neg_integer()) :: [KnowledgeBaseVersion.t()]
  defp find_timed_out_versions(org_id) do
    timeout_threshold = DateTime.utc_now() |> DateTime.add(-@timeout_hours * 3600, :second)

    KnowledgeBaseVersion
    |> where([kbv], kbv.organization_id == ^org_id)
    |> where([kbv], kbv.status == :in_progress)
    |> where([kbv], kbv.inserted_at < ^timeout_threshold)
    |> preload([:knowledge_base, assistant_config_versions: :assistant])
    |> Repo.all()
  end

  @spec mark_as_failed(KnowledgeBaseVersion.t()) ::
          {:ok, Notifications.Notification.t()} | {:error, Ecto.Changeset.t()}
  defp mark_as_failed(kbv) do
    Logger.warning("Marking KnowledgeBaseVersion #{kbv.id} as failed due to timeout")

    {:ok, _updated_kbv} =
      kbv
      |> KnowledgeBaseVersion.changeset(%{status: :failed})
      |> Repo.update()

    affected_acvs_with_preloads =
      kbv.assistant_config_versions
      |> Enum.filter(&(&1.status == :in_progress))

    affected_acv_ids = update_linked_config_versions(affected_acvs_with_preloads)

    send_timeout_notification(kbv, affected_acvs_with_preloads, affected_acv_ids)
  end

  @spec update_linked_config_versions([AssistantConfigVersion.t()]) :: [non_neg_integer()]
  defp update_linked_config_versions(acvs) do
    acvs
    |> Enum.map(fn acv ->
      {:ok, updated_acv} =
        acv
        |> AssistantConfigVersion.changeset(%{
          status: :failed,
          failure_reason: "Linked vector store creation timed out"
        })
        |> Repo.update()

      updated_acv.id
    end)
  end

  @spec send_timeout_notification(KnowledgeBaseVersion.t(), [AssistantConfigVersion.t()], [
          non_neg_integer()
        ]) ::
          {:ok, Notifications.Notification.t()} | {:error, Ecto.Changeset.t()}
  defp send_timeout_notification(kbv, affected_acvs_with_preloads, affected_acv_ids) do
    kb_name = kbv.knowledge_base.name

    affected_assistants =
      affected_acvs_with_preloads
      |> Enum.map(& &1.assistant)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.name)
      |> Enum.uniq()
      |> Enum.join(", ")

    message =
      if affected_assistants != "" do
        "Vector store '#{kb_name}' (version #{kbv.version_number}) creation timed out. Affected assistants: #{affected_assistants}"
      else
        "Vector store '#{kb_name}' (version #{kbv.version_number}) creation timed out."
      end

    Notifications.create_notification(%{
      category: "Assistant",
      message: message,
      severity: Notifications.types().warning,
      organization_id: kbv.organization_id,
      entity: %{
        knowledge_base_version_id: kbv.id,
        knowledge_base_id: kbv.knowledge_base_id,
        kaapi_job_id: kbv.kaapi_job_id,
        affected_config_version_ids: affected_acv_ids
      }
    })
  end
end
