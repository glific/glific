defmodule Glific.Assistants do
  @moduledoc """
  Context module for Assistant and related schemas
  """

  alias Glific.Assistants.Assistant
  alias Glific.Assistants.KnowledgeBase
  alias Glific.Assistants.KnowledgeBaseVersion
  alias Glific.Repo

  @doc """
  Creates an assistant
  """
  @spec create_assistant(map()) :: {:ok, Assistant.t()} | {:error, Ecto.Changeset.t()}
  def create_assistant(attrs) do
    %Assistant{}
    |> Assistant.changeset(attrs)
    |> Repo.insert()
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
  Updates the active config version for an assistant.

  **Important:** This function assumes the assistant exists.
  It is meant to be called immediately after creating the assistant.

  ## Raises
  - `Ecto.NoResultsError` if assistant doesn't exist
  """
  @spec update_assistant_active_config(non_neg_integer(), non_neg_integer()) ::
          {:ok, Assistant.t()} | {:error, Ecto.Changeset.t()}
  def update_assistant_active_config(assistant_id, config_version_id) do
    assistant = Repo.get!(Assistant, assistant_id)

    assistant
    |> Assistant.set_active_config_version_changeset(%{
      active_config_version_id: config_version_id
    })
    |> Repo.update()
  end
end
