defmodule Glific.Assistants do
  @moduledoc """
  Context module for Assistant and related schemas.
  """

  import Ecto.Query

  alias Glific.{
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Assistants.KnowledgeBase,
    Assistants.KnowledgeBaseVersion,
    Repo
  }

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
        from(cv in AssistantConfigVersion,
          where: cv.status == :in_progress
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

    acv = assistant.active_config_version

    new_version_in_progress =
      Enum.any?(assistant.config_versions, fn cv ->
        cv.id != assistant.active_config_version_id and cv.status == :in_progress
      end)

    %{
      id: assistant.id,
      name: assistant.name,
      assistant_id: assistant.kaapi_uuid,
      temperature: get_in(acv.settings || %{}, ["temperature"]),
      model: acv.model,
      instructions: acv.prompt,
      status: to_string(acv.status),
      new_version_in_progress: new_version_in_progress,
      vector_store_data: build_vector_store_data(acv),
      inserted_at: assistant.inserted_at,
      updated_at: assistant.updated_at
    }
  end

  defp build_vector_store_data(acv) do
    case acv.knowledge_base_versions do
      [kbv | _] ->
        kb = kbv.knowledge_base

        %{
          id: kb.id,
          vector_store_id: kbv.llm_service_id,
          name: kb.name,
          files: kbv.files || %{},
          size: kbv.size || 0,
          status: to_string(kbv.status),
          legacy: is_nil(kbv.kaapi_job_id),
          inserted_at: kbv.inserted_at,
          updated_at: kbv.updated_at
        }

      _ ->
        nil
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
