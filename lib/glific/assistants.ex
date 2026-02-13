defmodule Glific.Assistants do
  @moduledoc """
  Context module for Assistant and related schemas
  """

  require Logger

  alias Glific.{
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Assistants.KnowledgeBase,
    Assistants.KnowledgeBaseVersion,
    Repo,
    ThirdParty.Kaapi
  }

  @doc """
  Delete an assistant. If the assistant has a config version with a kaapi_uuid,
  deletes the config from Kaapi first (which removes all versions), then deletes
  the assistant from the database.
  """
  @spec delete_assistant(non_neg_integer()) ::
          {:ok, Assistant.t()} | {:error, any()}
  def delete_assistant(id) do
    with {:ok, assistant} <- Repo.fetch_by(Assistant, %{id: id}),
         assistant <- Repo.preload(assistant, :config_versions),
         :ok <-
           maybe_delete_config_from_kaapi(assistant.config_versions, assistant.organization_id) do
      Repo.delete(assistant)
    end
  end

  @spec maybe_delete_config_from_kaapi([AssistantConfigVersion.t()], non_neg_integer()) ::
          :ok | {:error, any()}
  defp maybe_delete_config_from_kaapi([], _organization_id), do: :ok

  defp maybe_delete_config_from_kaapi([config_version | _], organization_id) do
    case Kaapi.delete_config(config_version.kaapi_uuid, organization_id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
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
