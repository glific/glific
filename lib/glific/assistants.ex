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
end
