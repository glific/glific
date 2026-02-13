defmodule Glific.Assistants do
  @moduledoc """
  Context module for Assistant and related schemas
  """

  import Ecto.Query

  alias Glific.Assistants.Assistant
  alias Glific.Assistants.AssistantConfigVersion
  alias Glific.Assistants.KnowledgeBase
  alias Glific.Assistants.KnowledgeBaseVersion

  alias Glific.Repo
  alias Glific.ThirdParty.Kaapi

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
  Lists assistants from the unified API tables, transformed to legacy shape.
  """

  @spec list_assistants(map()) :: list(map())
  def list_assistants(args) do
    assistants =
      args
      |> Repo.list_filter_query(Assistant, &Repo.opts_with_inserted_at/2, &Repo.filter_with/2)
      |> Repo.all()
      |> preload_assistant_associations()

    Enum.map(assistants, &transform_to_legacy_shape/1)
  end

  @doc """
  Gets a single assistant from the unified API tables, transformed to legacy shape.
  """
  @spec get_assistant(integer()) :: {:ok, map()} | {:error, any()}
  def get_assistant(id) do
    with {:ok, assistant} <- Repo.fetch_by(Assistant, %{id: id}) do
      assistant = preload_assistant_associations(assistant)
      {:ok, transform_to_legacy_shape(assistant)}
    end
  end

  @spec preload_assistant_associations(Assistant.t() | list(Assistant.t())) ::
          Assistant.t() | list(Assistant.t())
  defp preload_assistant_associations(assistant_or_assistants) do
    Repo.preload(assistant_or_assistants, [
      {:active_config_version, [knowledge_base_versions: :knowledge_base]},
      config_versions:
        from(config_version in AssistantConfigVersion,
          where: config_version.status == :in_progress
        )
    ])
  end

  @spec transform_to_legacy_shape(Assistant.t()) :: map()
  defp transform_to_legacy_shape(%Assistant{} = assistant) do
    # new_version_in_progress - tracks whether a newer config version
    # (different from the active one) is being drafted, used by the frontend
    # for a "draft in progress" indicator.
    # legacy - identifies knowledge base versions created before the Kaapi
    # migration, which lack a kaapi_job_id since they were synced directly
    # via the OpenAI API.

    active_config_version = assistant.active_config_version

    new_version_in_progress =
      Enum.any?(assistant.config_versions, fn config_version ->
        config_version.id != assistant.active_config_version_id and
          config_version.status == :in_progress
      end)

    %{
      id: assistant.id,
      name: assistant.name,
      assistant_id: assistant.kaapi_uuid,
      temperature: get_in(active_config_version.settings || %{}, ["temperature"]),
      model: active_config_version.model,
      instructions: active_config_version.prompt,
      status: to_string(active_config_version.status),
      new_version_in_progress: new_version_in_progress,
      vector_store_data: build_vector_store_data(active_config_version),
      inserted_at: assistant.inserted_at,
      updated_at: assistant.updated_at
    }
  end

  defp build_vector_store_data(active_config_version) do
    [knowledge_base_version | _] = active_config_version.knowledge_base_versions
    knowledge_base = knowledge_base_version.knowledge_base

    %{
      id: knowledge_base.id,
      vector_store_id: knowledge_base_version.llm_service_id,
      name: knowledge_base.name,
      files: knowledge_base_version.files || %{},
      size: knowledge_base_version.size || 0,
      status: to_string(knowledge_base_version.status),
      legacy: is_nil(knowledge_base_version.kaapi_job_id),
      inserted_at: knowledge_base_version.inserted_at,
      updated_at: knowledge_base_version.updated_at
    }
  end
end
