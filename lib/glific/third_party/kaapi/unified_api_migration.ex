defmodule Glific.ThirdParty.Kaapi.UnifiedApiMigration do
  @moduledoc """
  This module provides functions for migrating Assistants data from the old structure to the new unified API structure.
  This should be deprecated and deleted once the migration is completed and unified API is fully functional.
  """

  import Ecto.Query
  require Logger

  alias Glific.Assistants
  alias Glific.Assistants.KnowledgeBase
  alias Glific.Assistants.KnowledgeBaseVersion
  alias Glific.Filesearch.Assistant
  alias Glific.Filesearch.VectorStore
  alias Glific.Repo
  alias Glific.TaskSupervisor

  @doc """
  Migrate assistant
  """
  @spec migrate_assistants :: nil
  def migrate_assistants do
    # Implementation of the migration logic
  end

  @doc """
  Migrate old vector stores to the new Unified API structure for maintaining versions
  """
  @spec migrate_vector_stores :: %{success: non_neg_integer(), failure: non_neg_integer()}
  def migrate_vector_stores do
    used_vector_stores =
      from(v in VectorStore,
        join: a in Assistant,
        on: v.id == a.vector_store_id,
        distinct: [v.id]
      )
      |> Repo.all()

    Task.Supervisor.async_stream_nolink(
      TaskSupervisor,
      used_vector_stores,
      &migrate_vector_store/1,
      max_concurrency: 20,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{success: 0, failure: 0}, fn
      {:ok, {:ok, _result}}, acc ->
        Map.update(acc, :success, 1, &(&1 + 1))

      {:ok, {:error, _changeset}}, acc ->
        Map.update(acc, :failure, 1, &(&1 + 1))

      {:exit, :timeout}, acc ->
        Logger.error("Vector Store Migration: Timed out")
        Map.update(acc, :failure, 1, &(&1 + 1))

      {:exit, _reason}, acc ->
        Map.update(acc, :failure, 1, &(&1 + 1))
    end)
  end

  # Private
  @spec migrate_vector_store(VectorStore.t()) ::
          {:ok, KnowledgeBaseVersion.t()} | {:error, Ecto.Changeset.t()}
  defp migrate_vector_store(vector_store) do
    Repo.put_process_state(vector_store.organization_id)

    attrs = %{
      llm_service_id: vector_store.vector_store_id,
      organization_id: vector_store.organization_id
    }

    case Repo.fetch_by(KnowledgeBaseVersion, attrs) do
      {:ok, knowledge_base_version} ->
        update_knowledge_base_version(knowledge_base_version, vector_store)

      _ ->
        # This can crash if the creation fails, but the chances of that is minimal,
        # and its okay for the process to crash if the creation fails.
        {:ok, knowledge_base} = create_knowledge_base(vector_store)
        create_knowledge_base_version(knowledge_base, vector_store)
    end
  end

  @spec create_knowledge_base(VectorStore.t()) ::
          {:ok, KnowledgeBase.t()} | {:error, Ecto.Changeset.t()}
  defp create_knowledge_base(vector_store) do
    attrs = %{name: vector_store.name, organization_id: vector_store.organization_id}

    case Assistants.create_knowledge_base(attrs) do
      {:ok, knowledge_base} ->
        {:ok, knowledge_base}

      {:error, reason} ->
        Logger.error(
          "Failed to create knowledge base for #{vector_store.vector_store_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @spec create_knowledge_base_version(KnowledgeBase.t(), VectorStore.t()) ::
          {:ok, KnowledgeBaseVersion.t()} | {:error, Ecto.Changeset.t()}
  defp create_knowledge_base_version(knowledge_base, vector_store) do
    attrs = %{
      knowledge_base_id: knowledge_base.id,
      organization_id: knowledge_base.organization_id,
      llm_service_id: vector_store.vector_store_id,
      files: vector_store.files,
      status: :completed,
      size: vector_store.size
    }

    case Assistants.create_knowledge_base_version(attrs) do
      {:ok, _knowledge_base_version} ->
        {:ok, knowledge_base}

      {:error, reason} ->
        Logger.error(
          "Failed to create knowledge base version for #{vector_store.vector_store_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @spec update_knowledge_base_version(KnowledgeBaseVersion.t(), VectorStore.t()) ::
          {:ok, KnowledgeBaseVersion.t()} | {:error, Ecto.Changeset.t()}
  defp update_knowledge_base_version(knowledge_base_version, vector_store) do
    attrs = %{files: vector_store.files, status: :completed, size: vector_store.size}

    knowledge_base_version
    |> KnowledgeBaseVersion.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, knowledge_base_version} ->
        {:ok, knowledge_base_version}

      {:error, reason} ->
        Logger.error(
          "Failed to update knowledge base version for #{vector_store.vector_store_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
