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

  @default_model "gpt-4o"

  @doc """
  Migrate all assistants to the new unified API structure
  """
  @spec migrate_assistants :: %{success: non_neg_integer(), failure: non_neg_integer()}
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
      max_concurrency: 20,
      timeout: 60_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{success: 0, failure: 0}, fn
      {:ok, {:ok, _result}}, acc ->
        Map.update(acc, :success, 1, &(&1 + 1))

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
          {:ok, Assistant.t()} | {:error, any()}
  defp migrate_assistant(openai_assistant) do
    Repo.put_process_state(openai_assistant.organization_id)

    # Check if already migrated
    case check_if_migrated(openai_assistant) do
      {:ok, existing_assistant} ->
        Logger.info(
          "Assistant #{openai_assistant.id} already migrated as #{existing_assistant.id}, skipping"
        )

        {:ok, existing_assistant}

      {:not_migrated} ->
        do_migrate_assistant(openai_assistant)
    end
  end

  @spec check_if_migrated(OpenAIAssistant.t()) :: {:ok, Assistant.t()} | {:not_migrated}
  defp check_if_migrated(openai_assistant) do
    case Repo.fetch_by(Assistant,
           name: openai_assistant.name,
           organization_id: openai_assistant.organization_id
         ) do
      {:ok, assistant} -> {:ok, assistant}
      _ -> {:not_migrated}
    end
  end

  @spec do_migrate_assistant(OpenAIAssistant.t()) ::
          {:ok, Assistant.t()} | {:error, any()}
  defp do_migrate_assistant(openai_assistant) do
    Logger.info("Migrating assistant #{openai_assistant.id}")

    org_id = openai_assistant.organization_id
    prompt = openai_assistant.instructions || "You are a helpful assistant"

    vector_store_ids = get_vector_store_ids(openai_assistant.vector_store)

    kb_version_id = get_kb_version_id(openai_assistant.vector_store)

    kaapi_params = %{
      name: openai_assistant.name,
      description: nil,
      prompt: prompt,
      assistant_id: openai_assistant.assistant_id,
      model: openai_assistant.model || @default_model,
      temperature: openai_assistant.temperature || 1,
      organization_id: org_id,
      vector_store_ids: vector_store_ids
    }

    with {:ok, kaapi_response} <- Kaapi.create_assistant_config(kaapi_params, org_id),
         kaapi_uuid = kaapi_response.data.id do
      multi_result =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(
          :assistant,
          Assistant.changeset(%Assistant{}, %{
            name: openai_assistant.name,
            description: nil,
            kaapi_uuid: kaapi_uuid,
            assistant_display_id: openai_assistant.assistant_id,
            organization_id: org_id
          })
        )
        |> Ecto.Multi.insert(:config_version, fn %{assistant: assistant} ->
          AssistantConfigVersion.changeset(%AssistantConfigVersion{}, %{
            assistant_id: assistant.id,
            prompt: prompt,
            model: kaapi_params.model,
            provider: "kaapi",
            settings: %{temperature: kaapi_params.temperature},
            status: :ready,
            organization_id: org_id,
            kaapi_uuid: kaapi_uuid
          })
        end)
        |> Ecto.Multi.update(:updated_assistant, fn %{
                                                      assistant: assistant,
                                                      config_version: config_version
                                                    } ->
          Assistant.set_active_config_version_changeset(assistant, %{
            active_config_version_id: config_version.id
          })
        end)
        |> Ecto.Multi.run(:link_kb, fn _repo, %{config_version: config_version} ->
          if kb_version_id do
            {count, _} = link_config_to_kb(config_version.id, kb_version_id, org_id)
            {:ok, count}
          else
            {:ok, 0}
          end
        end)
        |> Repo.transaction()

      case multi_result do
        {:ok, %{updated_assistant: assistant}} ->
          Logger.info("Successfully migrated assistant #{openai_assistant.id} to #{assistant.id}")
          {:ok, assistant}

        {:error, failed_operation, failed_value, _} ->
          Logger.error(
            "Failed at #{failed_operation} for assistant #{openai_assistant.id}: #{inspect(failed_value)}"
          )

          {:error, "Failed at #{failed_operation}: #{inspect(failed_value)}"}
      end
    else
      {:error, reason} ->
        Logger.error(
          "Kaapi config creation failed for assistant #{openai_assistant.id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @spec get_vector_store_ids(VectorStore.t() | nil) :: list(String.t())
  defp get_vector_store_ids(nil), do: []
  defp get_vector_store_ids(vector_store), do: [vector_store.vector_store_id]

  @spec get_kb_version_id(VectorStore.t() | nil) :: integer() | nil
  defp get_kb_version_id(nil), do: nil

  defp get_kb_version_id(vector_store) do
    case Repo.fetch_by(KnowledgeBaseVersion,
           llm_service_id: vector_store.vector_store_id,
           organization_id: vector_store.organization_id
         ) do
      {:ok, kb_version} -> kb_version.id
      _ -> nil
    end
  end

  @spec link_config_to_kb(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), nil | [term()]}
  defp link_config_to_kb(config_version_id, kb_version_id, org_id) do
    Repo.insert_all(
      "assistant_config_version_knowledge_base_versions",
      [
        %{
          assistant_config_version_id: config_version_id,
          knowledge_base_version_id: kb_version_id,
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
