defmodule Glific.Assistants do
  @moduledoc """
  Context module for Assistant and related schemas
  """

  import Ecto.Query
  require Logger

  alias Glific.Assistants.AssistantConfigVersion
  alias Glific.Assistants.KnowledgeBase
  alias Glific.Assistants.KnowledgeBaseVersion
  alias Glific.Notifications
  alias Glific.Repo

  @timeout_hours 1

  @doc """
  Create a Knowledge Base.

  ## Examples

  iex> Glific.Assistants.create_knowledge_base(%{name: "Test KB", organization_id: 1})
  {:ok, %KnowledgeBase{name: "Test KB", organization_id: 1}}

  iex> Glific.Assistants.create_knowledge_base(%{name: "", organization_id: 1})
  {:error, %Ecto.Changeset{}}
  """
  @spec create_knowledge_base(map()) :: {:ok, KnowledgeBase.t()} | {:error, Ecto.Changeset.t()}
  def create_knowledge_base(attrs) do
    %KnowledgeBase{}
    |> KnowledgeBase.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Create a Knowledge Base Version.

  ## Examples

  iex> Glific.Assistants.create_knowledge_base_version(%{llm_service_id: "KB_VS_ID1", organization_id: 1, knowledge_base_id: 1, files: [%{"name" => "file1", "size" => 100}], status: :ready, size: 100})
  {:ok, %KnowledgeBaseVersion{name: "Test KB", organization_id: 1}}

  iex> Glific.Assistants.create_knowledge_base_version(%{llm_service_id: nil, organization_id: 1})
  {:error, %Ecto.Changeset{}}
  """
  @spec create_knowledge_base_version(map()) ::
          {:ok, KnowledgeBaseVersion.t()} | {:error, Ecto.Changeset.t()}
  def create_knowledge_base_version(attrs) do
    %KnowledgeBaseVersion{}
    |> KnowledgeBaseVersion.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Periodically checks for in-progress KnowledgeBaseVersions that have exceeded
  the timeout threshold and marks them as failed.
  """
  @spec process_timeouts(non_neg_integer()) :: :ok
  def process_timeouts(org_id) do
    find_timed_out_versions(org_id)
    |> Enum.each(fn knowledge_base_version ->
      try do
        mark_as_failed(knowledge_base_version)
      rescue
        e ->
          Logger.error(
            "Failed to process timeout for KnowledgeBaseVersion #{knowledge_base_version.id}: #{Exception.message(e)}"
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
  defp mark_as_failed(knowledge_base_version) do
    Logger.warning(
      "Marking KnowledgeBaseVersion #{knowledge_base_version.id} as failed due to timeout"
    )

    {:ok, _updated} =
      knowledge_base_version
      |> KnowledgeBaseVersion.changeset(%{status: :failed})
      |> Repo.update()

    affected_config_versions =
      knowledge_base_version.assistant_config_versions
      |> Enum.filter(&(&1.status == :in_progress))

    affected_config_version_ids = update_linked_config_versions(affected_config_versions)

    send_timeout_notification(
      knowledge_base_version,
      affected_config_versions,
      affected_config_version_ids
    )
  end

  @spec update_linked_config_versions([AssistantConfigVersion.t()]) :: [non_neg_integer()]
  defp update_linked_config_versions(config_versions) do
    Enum.map(config_versions, fn config_version ->
      {:ok, updated} =
        config_version
        |> AssistantConfigVersion.changeset(%{
          status: :failed,
          failure_reason: "Linked vector store creation timed out"
        })
        |> Repo.update()

      updated.id
    end)
  end

  @spec send_timeout_notification(KnowledgeBaseVersion.t(), [AssistantConfigVersion.t()], [
          non_neg_integer()
        ]) ::
          {:ok, Notifications.Notification.t()} | {:error, Ecto.Changeset.t()}
  defp send_timeout_notification(
         knowledge_base_version,
         affected_config_versions,
         affected_config_version_ids
       ) do
    kb_name = knowledge_base_version.knowledge_base.name

    affected_assistants =
      affected_config_versions
      |> Enum.map(& &1.assistant)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.name)
      |> Enum.uniq()
      |> Enum.join(", ")

    message =
      if affected_assistants != "" do
        "Vector store '#{kb_name}' (version #{knowledge_base_version.version_number}) creation timed out. Affected assistants: #{affected_assistants}"
      else
        "Vector store '#{kb_name}' (version #{knowledge_base_version.version_number}) creation timed out."
      end

    Notifications.create_notification(%{
      category: "Assistant",
      message: message,
      severity: Notifications.types().warning,
      organization_id: knowledge_base_version.organization_id,
      entity: %{
        knowledge_base_version_id: knowledge_base_version.id,
        knowledge_base_id: knowledge_base_version.knowledge_base_id,
        kaapi_job_id: knowledge_base_version.kaapi_job_id,
        affected_config_version_ids: affected_config_version_ids
      }
    })
  end
end
