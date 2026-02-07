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

  @spec process_timeouts(non_neg_integer()) :: :ok
  def process_timeouts(org_id) do
    find_timed_out_versions(org_id)
    |> Enum.each(&mark_as_failed/1)

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

  @spec mark_as_failed(KnowledgeBaseVersion.t()) :: Notifications.Notification.t()
  defp mark_as_failed(kbv) do
    Logger.warning("Marking KnowledgeBaseVersion #{kbv.id} as failed due to timeout")

    kbv
    |> KnowledgeBaseVersion.changeset(%{status: :failed, failure_reason: @failure_reason})
    |> Repo.update()

    affected_cvs = update_linked_config_versions(kbv)

    send_timeout_notification(kbv, affected_cvs)
  end

  @spec update_linked_config_versions(KnowledgeBaseVersion.t()) :: [AssistantConfigVersion.t()]
  defp update_linked_config_versions(kbv) do
    kbv.assistant_config_versions
    |> Enum.filter(&(&1.status == :in_progress))
    |> Enum.map(fn acv ->
      acv
      |> AssistantConfigVersion.changeset(%{
        status: :failed,
        failure_reason: "Linked vector store creation timed out"
      })
      |> Repo.update()
    end)
  end

  @spec send_timeout_notification(KnowledgeBaseVersion.t(), [AssistantConfigVersion.t()]) ::
          {:ok, Notifications.Notification.t()} | {:error, Ecto.Changeset.t()}
  defp send_timeout_notification(kbv, affected_cvs) do
    kb_name = kbv.knowledge_base.name

    affected_assistants =
      affected_cvs
      |> Enum.map(&if(&1.assistant, do: &1.assistant.name, else: "Unknown"))
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
        affected_config_version_ids: Enum.map(affected_cvs, & &1.id)
      }
    })
  end
end
