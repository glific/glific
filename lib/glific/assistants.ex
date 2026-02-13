defmodule Glific.Assistants do
  @moduledoc """
  Context module for Assistant and related schemas
  """

  require Logger

  alias Glific.{
    Assistants.Assistant,
    Assistants.KnowledgeBase,
    Assistants.KnowledgeBaseVersion,
    Repo,
    ThirdParty.Kaapi
  }

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

      error ->
        {:error, "Failed to delete assistant from Kaapi: #{inspect(error)}"}
    end
  end

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
end
