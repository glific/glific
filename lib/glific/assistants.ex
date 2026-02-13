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
  alias Glific.ThirdParty.Kaapi

  @timeout_hours 1
  # https://platform.openai.com/docs/assistants/tools/file-search#supported-files
  @assistant_supported_file_extensions [
    "csv",
    "doc",
    "docx",
    "html",
    "java",
    "md",
    "pdf",
    "pptx",
    "txt"
  ]

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
  Upload file to Kaapi documents API

  ## Parameters
    - params: Map containing:
      - media: Required. Map with:
        - path: Required. File path of the document to upload
        - filename: Required. Name of the file being uploaded
      - target_format: Optional. Desired output format (e.g., pdf, docx, txt) only pdf to markdown is available now
      - callback_url: Optional. URL to call for transformation status updates

  ## Returns
    - {:ok, %{file_id: string, filename: string}}
    - {:error, reason}
  """
  @spec upload_file(map(), non_neg_integer()) ::
          {:ok, map()} | {:error, String.t()}
  def upload_file(params, organization_id) do
    document_params = %{
      path: params.media.path,
      filename: params.media.filename,
      target_format: params[:target_format],
      callback_url: params[:callback_url]
    }

    with {:ok, _} <- validate_file_format(params.media.filename),
         {:ok, %{data: document_data}} <- Kaapi.upload_document(document_params, organization_id) do
      {:ok,
       %{
         file_id: document_data[:id],
         filename: document_data[:fname],
         uploaded_at: document_data[:inserted_at]
       }}
    else
      {:error, %{status: status, body: body}} ->
        error_message = body[:error]
        {:error, "File upload failed (status #{status}): #{error_message}"}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "File upload failed: #{inspect(reason)}"}
    end
  end

  @spec validate_file_format(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp validate_file_format(filename) do
    extension = String.split(filename, ".") |> List.last()

    if extension in @assistant_supported_file_extensions do
      {:ok, filename}
    else
      {:error, "Files with extension '.#{extension}' not supported in Assistants"}
    end
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
    affected_assistant_names =
      affected_config_versions
      |> Enum.map(& &1.assistant)
      |> Enum.map(& &1.name)
      |> Enum.uniq()

    Notifications.create_notification(%{
      category: "Assistant",
      message: "Knowledge Base creation timeout",
      severity: Notifications.types().warning,
      organization_id: knowledge_base_version.organization_id,
      entity: %{
        knowledge_base_version_id: knowledge_base_version.id,
        knowledge_base_id: knowledge_base_version.knowledge_base_id,
        knowledge_base_name: knowledge_base_version.knowledge_base.name,
        version_number: knowledge_base_version.version_number,
        kaapi_job_id: knowledge_base_version.kaapi_job_id,
        affected_config_version_ids: affected_config_version_ids,
        affected_assistant_names: affected_assistant_names
      }
    })
  end
end
