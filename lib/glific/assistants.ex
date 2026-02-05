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

    assistants =
      Repo.preload(assistants, [
        {:active_config_version, [knowledge_base_versions: :knowledge_base]},
        config_versions:
          from(cv in AssistantConfigVersion,
            where: cv.status == :in_progress
          )
      ])

    Enum.map(assistants, &transform_to_legacy_shape/1)
  end

  @doc """
  Gets a single assistant from the unified API tables, transformed to legacy shape.
  """
  @spec get_assistant(integer()) :: {:ok, map()} | {:error, any()}
  def get_assistant(id) do
    with {:ok, assistant} <- Repo.fetch_by(Assistant, %{id: id}) do
      assistant =
        Repo.preload(assistant, [
          {:active_config_version, [knowledge_base_versions: :knowledge_base]},
          config_versions:
            from(cv in AssistantConfigVersion,
              where: cv.status == :in_progress
            )
        ])

      {:ok, transform_to_legacy_shape(assistant)}
    end
  end

  @doc """
  Gets an assistant by kaapi_uuid. Finds the assistant_id, then calls get_assistant/1.
  """
  @spec get_assistant_by_kaapi_uuid(String.t()) :: {:ok, map()} | {:error, any()}
  def get_assistant_by_kaapi_uuid(kaapi_uuid) do
    case Repo.one(
           from(acv in AssistantConfigVersion,
             where: acv.kaapi_uuid == ^kaapi_uuid,
             select: acv.assistant_id
           )
         ) do
      nil -> {:error, "Assistant not found"}
      assistant_id -> get_assistant(assistant_id)
    end
  end

  @doc """
  Transforms a unified API Assistant struct into a map matching the legacy
  GraphQL assistant response shape.
  """
  @spec transform_to_legacy_shape(Assistant.t()) :: map()
  def transform_to_legacy_shape(%Assistant{} = assistant) do
    acv = assistant.active_config_version

    new_version_in_progress =
      case assistant.config_versions do
        versions when is_list(versions) ->
          Enum.any?(versions, fn cv ->
            cv.id != assistant.active_config_version_id and cv.status == :in_progress
          end)

        _ ->
          false
      end

    %{
      id: assistant.id,
      name: assistant.name,
      assistant_id: acv.kaapi_uuid,
      temperature: get_in(acv.settings || %{}, ["temperature"]),
      model: acv.model,
      instructions: acv.prompt,
      status: to_string(acv.status),
      new_version_in_progress: new_version_in_progress,
      __vector_store_data__: build_vector_store_data(acv),
      inserted_at: assistant.inserted_at,
      updated_at: assistant.updated_at
    }
  end

  @doc """
  Gets vector store data from new tables by kaapi_uuid.
  Used when mutations return legacy Filesearch.Assistant structs.
  """
  @spec get_vector_store_by_kaapi_uuid(String.t()) :: map() | nil
  def get_vector_store_by_kaapi_uuid(kaapi_uuid) do
    case Repo.one(
           from(acv in AssistantConfigVersion,
             where: acv.kaapi_uuid == ^kaapi_uuid,
             preload: [knowledge_base_versions: :knowledge_base]
           )
         ) do
      nil -> nil
      acv -> build_vector_store_data(acv)
    end
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
