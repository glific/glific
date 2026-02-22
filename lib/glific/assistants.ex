defmodule Glific.Assistants do
  @moduledoc """
  Context module for Assistant and related schemas
  """

  import Ecto.Query

  require Logger

  alias Ecto.Multi
  alias Glific.Assistants.Assistant
  alias Glific.Assistants.AssistantConfigVersion
  alias Glific.Assistants.KnowledgeBase
  alias Glific.Assistants.KnowledgeBaseVersion
  alias Glific.Notifications
  alias Glific.Repo
  alias Glific.ThirdParty.Kaapi

  @timeout_hours 1

  @default_model "gpt-4o"

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
  Creates an Assistant
  """
  @spec create_assistant(map()) :: {:ok, map()} | {:error, any()}
  def create_assistant(user_params) do
    with :ok <- validate_knowledge_base_presence(user_params),
         {:ok, knowledge_base_version} <-
           KnowledgeBaseVersion.get_knowledge_base_version(user_params[:knowledge_base_id]),
         {:ok, kaapi_config} <- build_kaapi_config(user_params, knowledge_base_version) do
      create_assistant_transaction(kaapi_config, knowledge_base_version)
    end
  end

  @spec validate_knowledge_base_presence(map()) :: :ok | {:error, String.t()}
  defp validate_knowledge_base_presence(user_params) do
    if is_nil(user_params[:knowledge_base_id]) do
      {:error, "Knowledge base is required for assistant creation"}
    else
      :ok
    end
  end

  @spec build_kaapi_config(map(), KnowledgeBaseVersion.t()) :: {:ok, map()}
  defp build_kaapi_config(user_params, knowledge_base_version) do
    prompt = user_params[:instructions] || "You are a helpful assistant"
    description = user_params[:description] || "Assistant configuration"

    config = %{
      temperature: user_params[:temperature] || 1,
      model: user_params[:model] || @default_model,
      organization_id: user_params[:organization_id],
      name: generate_assistant_name(user_params[:name]),
      description: description,
      vector_store_ids: [knowledge_base_version.llm_service_id],
      prompt: prompt
    }

    {:ok, config}
  end

  @spec create_assistant_transaction(map(), KnowledgeBaseVersion.t()) ::
          {:ok, map()} | {:error, any()}
  defp create_assistant_transaction(kaapi_config, knowledge_base_version) do
    Multi.new()
    |> Multi.insert(:assistant, build_assistant_changeset(kaapi_config))
    |> Multi.insert(
      :config_version,
      &build_config_version_changeset(&1.assistant, kaapi_config, knowledge_base_version)
    )
    |> Multi.update(:assistant_with_active_config, fn %{
                                                        assistant: assistant,
                                                        config_version: config_version
                                                      } ->
      Assistant.set_active_config_version_changeset(assistant, %{
        active_config_version_id: config_version.id
      })
    end)
    |> Multi.insert_all(
      :link_knowledge_base,
      "assistant_config_version_knowledge_base_versions",
      &build_knowledge_base_link(
        &1.config_version,
        knowledge_base_version,
        kaapi_config.organization_id
      )
    )
    |> Multi.run(:kaapi_uuid, fn _repo, _changes ->
      create_kaapi_assistant(kaapi_config, kaapi_config.organization_id)
    end)
    |> Multi.update(:updated_assistant, fn %{
                                             assistant_with_active_config: assistant,
                                             kaapi_uuid: kaapi_uuid
                                           } ->
      Assistant.changeset(assistant, %{kaapi_uuid: kaapi_uuid})
    end)
    |> Repo.transaction()
    |> handle_transaction_result()
  end

  @spec build_knowledge_base_link(
          AssistantConfigVersion.t(),
          KnowledgeBaseVersion.t(),
          non_neg_integer()
        ) :: [map()]
  defp build_knowledge_base_link(config_version, knowledge_base_version, organization_id) do
    [
      %{
        assistant_config_version_id: config_version.id,
        knowledge_base_version_id: knowledge_base_version.id,
        organization_id: organization_id,
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
    ]
  end

  @spec build_assistant_changeset(map()) :: Ecto.Changeset.t()
  defp build_assistant_changeset(kaapi_config) do
    Assistant.changeset(%Assistant{}, %{
      name: kaapi_config.name,
      description: kaapi_config.prompt,
      organization_id: kaapi_config.organization_id
    })
  end

  @spec build_config_version_changeset(Assistant.t(), map(), KnowledgeBaseVersion.t()) ::
          Ecto.Changeset.t()
  defp build_config_version_changeset(assistant, kaapi_config, knowledge_base_version) do
    status =
      if knowledge_base_version.status == :completed,
        do: :ready,
        else: knowledge_base_version.status

    AssistantConfigVersion.changeset(%AssistantConfigVersion{}, %{
      assistant_id: assistant.id,
      description: kaapi_config.description,
      prompt: kaapi_config.prompt,
      model: kaapi_config.model,
      provider: "kaapi",
      settings: %{temperature: kaapi_config.temperature},
      status: status,
      organization_id: kaapi_config.organization_id
    })
  end

  @spec create_kaapi_assistant(map(), non_neg_integer()) :: {:ok, String.t()} | {:error, any()}
  defp create_kaapi_assistant(kaapi_config, organization_id) do
    case Kaapi.create_assistant_config(kaapi_config, organization_id) do
      {:ok, kaapi_response} ->
        {:ok, kaapi_response.data.id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec handle_transaction_result({:ok, map()} | {:error, atom(), any(), map()}) ::
          {:ok, map()} | {:error, any()}
  defp handle_transaction_result(result) do
    case result do
      {:ok, %{updated_assistant: assistant, config_version: config_version}} ->
        {:ok, %{assistant: assistant, config_version: config_version}}

      {:error, _failed, %Ecto.Changeset{} = changeset, _} ->
        {:error, changeset}

      {:error, failed_operation, failed_value, _changes_so_far} ->
        Logger.error("Failed at #{failed_operation}: #{inspect(failed_value)}")
        {:error, "Failed at #{failed_operation}: #{inspect(failed_value)}"}
    end
  end

  @spec generate_assistant_name(String.t() | nil) :: String.t()
  defp generate_assistant_name(name) when name in [nil, ""] do
    uid = Ecto.UUID.generate() |> String.split("-") |> List.first()
    "Assistant-#{uid}"
  end

  defp generate_assistant_name(name), do: name

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

  @doc """
  Delete an assistant. If the assistant has a kaapi_uuid,
  deletes the config and assistant from Kaapi first, then deletes
  the assistant from the database.
  """
  @spec delete_assistant(non_neg_integer()) ::
          {:ok, Assistant.t()} | {:error, any()}
  def delete_assistant(id) do
    with {:ok, assistant} <- Repo.fetch_by(Assistant, %{id: id}),
         :ok <- delete_from_kaapi(assistant.kaapi_uuid, assistant.organization_id) do
      Repo.delete(assistant)
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
  Checks for in-progress KnowledgeBaseVersions that have exceeded
  """
  @spec process_timeouts(non_neg_integer()) :: :ok
  def process_timeouts(org_id) do
    org_id
    |> find_timed_out_versions()
    |> Enum.each(fn knowledge_base_version ->
      mark_as_failed(knowledge_base_version)
    end)

    :ok
  end

  @spec find_timed_out_versions(non_neg_integer()) :: [KnowledgeBaseVersion.t()]
  defp find_timed_out_versions(org_id) do
    timeout_threshold = DateTime.utc_now() |> DateTime.add(-@timeout_hours, :hour)

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
        affected_config_version_ids: affected_config_version_ids,
        affected_assistant_names: affected_assistant_names
      }
    })
  end

  @doc false
  @spec delete_from_kaapi(String.t() | nil, non_neg_integer()) ::
          :ok | {:error, any()}
  defp delete_from_kaapi(nil, _organization_id), do: :ok

  defp delete_from_kaapi(kaapi_uuid, organization_id) do
    with {:ok, _} <- Kaapi.delete_config(kaapi_uuid, organization_id),
         {:ok, _} <- Kaapi.delete_assistant(kaapi_uuid, organization_id) do
      :ok
    else
      {:error, reason} ->
        {:error, "Failed to delete assistant from Kaapi: #{inspect(reason)}"}
    end
  end
end
