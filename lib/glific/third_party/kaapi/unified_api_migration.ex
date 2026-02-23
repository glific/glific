defmodule Glific.ThirdParty.Kaapi.UnifiedApiMigration do
  @moduledoc """
  This module provides functions for migrating Assistants data from the old structure to the new unified API structure.
  This should be deprecated and deleted once the migration is completed and unified API is fully functional.
  """

  import Ecto.Query
  require Logger

  alias Glific.Assistants
  alias Glific.Assistants.Assistant
  alias Glific.Assistants.AssistantConfigVersion
  alias Glific.Assistants.KnowledgeBase
  alias Glific.Assistants.KnowledgeBaseVersion
  alias Glific.Filesearch.Assistant, as: OpenAIAssistant
  alias Glific.Filesearch.VectorStore
  alias Glific.Repo
  alias Glific.TaskSupervisor
  alias Glific.ThirdParty.Kaapi

  @doc """
  Migrate all assistants to the new unified API structure
  """
  @spec migrate_assistants :: %{
          success: non_neg_integer(),
          failure: non_neg_integer(),
          skipped: non_neg_integer()
        }
  def migrate_assistants do
    openai_assistants =
      from(oa in OpenAIAssistant,
        preload: [:vector_store]
      )
      |> Repo.all()

    Logger.info("Starting migration for #{length(openai_assistants)} assistants")

    Task.Supervisor.async_stream_nolink(
      TaskSupervisor,
      openai_assistants,
      &migrate_assistant/1,
      max_concurrency: 5,
      timeout: 60_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{success: 0, failure: 0, skipped: 0}, fn
      {:ok, {:ok, _result}}, acc ->
        Map.update(acc, :success, 1, &(&1 + 1))

      {:ok, :skipped}, acc ->
        Map.update(acc, :skipped, 1, &(&1 + 1))

      {:ok, {:error, reason}}, acc ->
        Logger.error("Assistant Migration failed: #{inspect(reason)}")
        Map.update(acc, :failure, 1, &(&1 + 1))

      {:exit, :timeout}, acc ->
        Logger.error("Assistant Migration: Timed out")
        Map.update(acc, :failure, 1, &(&1 + 1))

      {:exit, reason}, acc ->
        Logger.error("Assistant Migration: Exited with reason: #{inspect(reason)}")
        Map.update(acc, :failure, 1, &(&1 + 1))
    end)
  end

  # Private functions
  @spec migrate_assistant(OpenAIAssistant.t()) ::
          {:ok, Assistant.t()} | {:error, any()} | :skipped
  defp migrate_assistant(openai_assistant) do
    Repo.put_process_state(openai_assistant.organization_id)

    # Check if already migrated
    case check_if_migrated(openai_assistant) do
      {:ok, existing_assistant} ->
        Logger.info(
          "Assistant #{openai_assistant.id} already migrated as #{existing_assistant.id}, skipping"
        )

        :skipped

      :not_migrated ->
        do_migrate_assistant(openai_assistant)
    end
  end

  @spec check_if_migrated(OpenAIAssistant.t()) :: {:ok, Assistant.t()} | :not_migrated
  defp check_if_migrated(openai_assistant) do
    case Repo.fetch_by(Assistant,
           name: openai_assistant.name,
           organization_id: openai_assistant.organization_id
         ) do
      {:ok, assistant} -> {:ok, assistant}
      _ -> :not_migrated
    end
  end

  @spec do_migrate_assistant(OpenAIAssistant.t()) ::
          {:ok, Assistant.t()} | {:error, any()}
  defp do_migrate_assistant(openai_assistant) do
    Logger.info("Migrating assistant #{openai_assistant.id}")
    kaapi_params = build_kaapi_params(openai_assistant)

    case Kaapi.create_assistant_config(kaapi_params, openai_assistant.organization_id) do
      {:ok, kaapi_response} ->
        openai_assistant
        |> build_migration_multi(kaapi_params, kaapi_response.data.id)
        |> Repo.transaction()
        |> handle_transaction_result(openai_assistant)

      {:error, reason} ->
        Logger.error(
          "Kaapi config creation failed for assistant #{openai_assistant.id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @spec build_kaapi_params(OpenAIAssistant.t()) :: map()
  defp build_kaapi_params(openai_assistant) do
    %{
      name: openai_assistant.name,
      description: nil,
      prompt: openai_assistant.instructions,
      assistant_id: openai_assistant.assistant_id,
      model: openai_assistant.model,
      temperature: openai_assistant.temperature,
      organization_id: openai_assistant.organization_id,
      vector_store_ids: get_vector_store_ids(openai_assistant.vector_store)
    }
  end

  @spec build_migration_multi(OpenAIAssistant.t(), map(), String.t()) :: Ecto.Multi.t()
  defp build_migration_multi(openai_assistant, kaapi_params, kaapi_uuid) do
    knowledge_base_version_id = get_knowledge_base_version_id(openai_assistant.vector_store)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:assistant, build_assistant_changeset(openai_assistant, kaapi_uuid))
    |> Ecto.Multi.insert(
      :config_version,
      build_config_version_changeset(kaapi_params, kaapi_uuid)
    )
    |> Ecto.Multi.update(:updated_assistant, &build_active_config_changeset/1)
    |> Ecto.Multi.run(:link_knowledge_base, fn _repo, %{config_version: config_version} ->
      link_knowledge_base_version(
        config_version.id,
        knowledge_base_version_id,
        kaapi_params.organization_id
      )
    end)
  end

  @spec build_assistant_changeset(OpenAIAssistant.t(), String.t()) :: Ecto.Changeset.t()
  defp build_assistant_changeset(openai_assistant, kaapi_uuid) do
    Assistant.changeset(%Assistant{}, %{
      name: openai_assistant.name,
      kaapi_uuid: kaapi_uuid,
      assistant_display_id: openai_assistant.assistant_id,
      organization_id: openai_assistant.organization_id,
      inserted_at: openai_assistant.inserted_at
    })
  end

  @spec build_config_version_changeset(map(), String.t()) :: (map() -> Ecto.Changeset.t())
  defp build_config_version_changeset(kaapi_params, kaapi_uuid) do
    fn %{assistant: assistant} ->
      AssistantConfigVersion.changeset(%AssistantConfigVersion{}, %{
        assistant_id: assistant.id,
        prompt: kaapi_params.prompt,
        model: kaapi_params.model,
        provider: "kaapi",
        settings: %{temperature: kaapi_params.temperature},
        status: :ready,
        organization_id: kaapi_params.organization_id,
        kaapi_uuid: kaapi_uuid
      })
    end
  end

  @spec build_active_config_changeset(map()) :: Ecto.Changeset.t()
  defp build_active_config_changeset(%{assistant: assistant, config_version: config_version}) do
    Assistant.set_active_config_version_changeset(assistant, %{
      active_config_version_id: config_version.id
    })
  end

  @spec link_knowledge_base_version(non_neg_integer(), non_neg_integer() | nil, non_neg_integer()) ::
          {:ok, non_neg_integer()}
  defp link_knowledge_base_version(_config_version_id, nil, _org_id), do: {:ok, 0}

  defp link_knowledge_base_version(config_version_id, knowledge_base_version_id, org_id) do
    {count, _} =
      link_config_to_knowledge_base(config_version_id, knowledge_base_version_id, org_id)

    {:ok, count}
  end

  @spec handle_transaction_result(
          {:ok, map()} | {:error, atom(), any(), map()},
          OpenAIAssistant.t()
        ) :: {:ok, Assistant.t()} | {:error, String.t()}
  defp handle_transaction_result({:ok, %{updated_assistant: assistant}}, openai_assistant) do
    Logger.info("Successfully migrated assistant #{openai_assistant.id} to #{assistant.id}")
    {:ok, assistant}
  end

  defp handle_transaction_result({:error, failed_operation, failed_value, _}, openai_assistant) do
    Logger.error(
      "Assistant creation failed at #{failed_operation} for assistant #{openai_assistant.id}: #{inspect(failed_value)}"
    )

    {:error, "Assistant creation Failed at #{failed_operation}: #{inspect(failed_value)}"}
  end

  @spec get_vector_store_ids(VectorStore.t() | nil) :: list(String.t())
  defp get_vector_store_ids(nil), do: []
  defp get_vector_store_ids(vector_store), do: [vector_store.vector_store_id]

  @spec get_knowledge_base_version_id(VectorStore.t() | nil) :: integer() | nil
  defp get_knowledge_base_version_id(nil), do: nil

  defp get_knowledge_base_version_id(vector_store) do
    case Repo.fetch_by(KnowledgeBaseVersion,
           llm_service_id: vector_store.vector_store_id,
           organization_id: vector_store.organization_id
         ) do
      {:ok, knowledge_base_version} -> knowledge_base_version.id
      _ -> nil
    end
  end

  @spec link_config_to_knowledge_base(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), nil | [term()]}
  defp link_config_to_knowledge_base(config_version_id, knowledge_base_version_id, org_id) do
    Repo.insert_all(
      "assistant_config_version_knowledge_base_versions",
      [
        %{
          assistant_config_version_id: config_version_id,
          knowledge_base_version_id: knowledge_base_version_id,
          organization_id: org_id,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
      ]
    )
  end

  # Vector store migration functions (keep existing code)
  @doc """
  Migrate old vector stores to the new Unified API structure for maintaining versions
  """
  @spec migrate_vector_stores :: %{success: non_neg_integer(), failure: non_neg_integer()}
  def migrate_vector_stores do
    used_vector_stores =
      from(v in VectorStore,
        join: a in OpenAIAssistant,
        on: v.id == a.vector_store_id,
        distinct: [v.id]
      )
      |> Repo.all()

    Task.Supervisor.async_stream_nolink(
      TaskSupervisor,
      used_vector_stores,
      &migrate_vector_store/1,
      max_concurrency: 5,
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
      {:ok, knowledge_base_version} ->
        {:ok, knowledge_base_version}

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
