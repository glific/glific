defmodule Glific.ThirdParty.Kaapi.UnifiedApiMigrationTest do
  use Glific.DataCase

  alias Ecto.Changeset
  alias Glific.Assistants
  alias Glific.Assistants.Assistant
  alias Glific.Assistants.AssistantConfigVersion
  alias Glific.Assistants.KnowledgeBase
  alias Glific.Assistants.KnowledgeBaseVersion
  alias Glific.Filesearch.Assistant, as: OpenAIAssistant
  alias Glific.Filesearch.VectorStore
  alias Glific.Partners
  alias Glific.Repo
  alias Glific.ThirdParty.Kaapi.UnifiedApiMigration

  describe "migrate_vector_stores/0" do
    setup %{organization_id: organization_id} do
      vector_stores = create_vector_store_with_assistant(organization_id, 10)
      vector_stores_count = Enum.count(vector_stores)
      %{vector_stores: vector_stores, count: vector_stores_count}
    end

    test "successfully migrates all vector stores with assistants", %{
      vector_stores: vector_stores,
      count: vector_stores_count
    } do
      assert %{success: vector_stores_count, failure: 0} ==
               UnifiedApiMigration.migrate_vector_stores()

      assert Repo.aggregate(KnowledgeBase, :count, :id) == vector_stores_count
      assert Repo.aggregate(KnowledgeBaseVersion, :count, :id) == vector_stores_count

      for vector_store <- vector_stores do
        assert_vector_migration(vector_store)
      end
    end

    test "skips vector stores without assistants", %{
      vector_stores: vector_stores,
      count: vector_stores_count,
      organization_id: organization_id
    } do
      vector_stores_without_assistants = create_vector_store_without_assistant(organization_id, 5)

      assert %{success: vector_stores_count, failure: 0} ==
               UnifiedApiMigration.migrate_vector_stores()

      assert Repo.aggregate(KnowledgeBase, :count, :id) == vector_stores_count
      assert Repo.aggregate(KnowledgeBaseVersion, :count, :id) == vector_stores_count

      for vector_store <- vector_stores do
        assert_vector_migration(vector_store)
      end

      for vector_store <- vector_stores_without_assistants do
        assert {:error, ["Elixir.Glific.Assistants.KnowledgeBase", "Resource not found"]} =
                 Repo.fetch_by(KnowledgeBase, %{name: vector_store.name})

        {:error, ["Elixir.Glific.Assistants.KnowledgeBaseVersion", "Resource not found"]} =
          Repo.fetch_by(KnowledgeBaseVersion, %{llm_service_id: vector_store.vector_store_id})
      end
    end

    test "updates knowledge base version of already migrated vector stores", %{
      vector_stores: vector_stores,
      count: vector_stores_count
    } do
      assert %{success: vector_stores_count, failure: 0} ==
               UnifiedApiMigration.migrate_vector_stores()

      assert Repo.aggregate(KnowledgeBase, :count, :id) == vector_stores_count
      assert Repo.aggregate(KnowledgeBaseVersion, :count, :id) == vector_stores_count

      updated_vector_stores =
        vector_stores |> Enum.take_random(5) |> Enum.map(&(update_vector_store(&1) |> elem(1)))

      assert %{success: vector_stores_count, failure: 0} ==
               UnifiedApiMigration.migrate_vector_stores()

      assert Repo.aggregate(KnowledgeBase, :count, :id) == vector_stores_count
      assert Repo.aggregate(KnowledgeBaseVersion, :count, :id) == vector_stores_count

      for vector_store <- updated_vector_stores do
        assert_vector_migration(vector_store)
      end
    end

    test "does not migrate same vector store multiple times if used by multiple assistants", %{
      vector_stores: vector_stores,
      count: vector_stores_count
    } do
      for vector_store <- vector_stores do
        create_openai_assistant(vector_store.organization_id, vector_store)
      end

      assert %{success: vector_stores_count, failure: 0} ==
               UnifiedApiMigration.migrate_vector_stores()

      assert Repo.aggregate(KnowledgeBase, :count, :id) == vector_stores_count
      assert Repo.aggregate(KnowledgeBaseVersion, :count, :id) == vector_stores_count

      for vector_store <- vector_stores do
        assert_vector_migration(vector_store)
      end
    end
  end

  describe "migrate_assistants/0" do
    setup %{organization_id: organization_id} do
      enable_kaapi(%{organization_id: organization_id})

      Tesla.Mock.mock_global(fn
        %{method: :post} ->
          {:ok,
           %Tesla.Env{
             status: 201,
             body: %{
               success: true,
               data: %{
                 id: Faker.UUID.v4(),
                 name: "test config"
               }
             }
           }}
      end)

      :ok
    end

    test "successfully migrates all openai assistants", %{organization_id: organization_id} do
      vector_store = create_and_insert_vector_store(organization_id)
      openai_assistants = create_openai_assistants(organization_id, vector_store, 3)

      result = UnifiedApiMigration.migrate_assistants()

      assert result.success == length(openai_assistants)
      assert result.failure == 0

      assert Repo.aggregate(Assistant, :count, :id) == length(openai_assistants)
      assert Repo.aggregate(AssistantConfigVersion, :count, :id) == length(openai_assistants)

      for openai_assistant <- openai_assistants do
        assert_assistant_migration(openai_assistant)
      end
    end

    test "skips already migrated assistants", %{organization_id: organization_id} do
      vector_store = create_and_insert_vector_store(organization_id)
      openai_assistants = create_openai_assistants(organization_id, vector_store, 3)

      first_result = UnifiedApiMigration.migrate_assistants()
      assert first_result.success == length(openai_assistants)
      assert first_result.failure == 0

      # Re-run — no new Kaapi calls since all are already migrated
      second_result = UnifiedApiMigration.migrate_assistants()
      assert second_result.skipped == length(openai_assistants)
      assert second_result.success == 0
      assert second_result.failure == 0

      # Counts should not double
      assert Repo.aggregate(Assistant, :count, :id) == length(openai_assistants)
      assert Repo.aggregate(AssistantConfigVersion, :count, :id) == length(openai_assistants)
    end

    test "migrates assistant without a vector store", %{organization_id: organization_id} do
      openai_assistant = create_openai_assistant(organization_id, nil)

      result = UnifiedApiMigration.migrate_assistants()

      assert result.success == 1
      assert result.failure == 0

      assert_assistant_migration(openai_assistant)
    end

    test "links knowledge base version when vector store has been migrated", %{
      organization_id: organization_id
    } do
      vector_store = create_and_insert_vector_store(organization_id)

      {:ok, kb} =
        Assistants.create_knowledge_base(%{
          name: vector_store.name,
          organization_id: organization_id
        })

      {:ok, kb_version} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: kb.id,
          organization_id: organization_id,
          llm_service_id: vector_store.vector_store_id,
          files: vector_store.files,
          status: :completed,
          size: vector_store.size
        })

      openai_assistant = create_openai_assistant(organization_id, vector_store)

      result = UnifiedApiMigration.migrate_assistants()
      assert result.success == 1

      {:ok, assistant} =
        Repo.fetch_by(Assistant, %{
          name: openai_assistant.name,
          organization_id: organization_id
        })

      {:ok, config_version} =
        Repo.fetch_by(AssistantConfigVersion, %{assistant_id: assistant.id})

      config_version = Repo.preload(config_version, :knowledge_base_versions)
      assert length(config_version.knowledge_base_versions) == 1
      assert List.first(config_version.knowledge_base_versions).id == kb_version.id
    end

    test "does not link knowledge base version when vector store is not yet migrated", %{
      organization_id: organization_id
    } do
      vector_store = create_and_insert_vector_store(organization_id)
      openai_assistant = create_openai_assistant(organization_id, vector_store)

      result = UnifiedApiMigration.migrate_assistants()
      assert result.success == 1

      {:ok, assistant} =
        Repo.fetch_by(Assistant, %{
          name: openai_assistant.name,
          organization_id: organization_id
        })

      {:ok, config_version} =
        Repo.fetch_by(AssistantConfigVersion, %{assistant_id: assistant.id})

      config_version = Repo.preload(config_version, :knowledge_base_versions)
      assert config_version.knowledge_base_versions == []
    end

    test "handles kaapi config creation failure gracefully", %{organization_id: organization_id} do
      openai_assistants = create_openai_assistants(organization_id, nil, 3)

      Tesla.Mock.mock_global(fn %{method: :post} ->
        {:ok, %Tesla.Env{status: 500, body: %{success: false, error: "Internal Server Error"}}}
      end)

      result = UnifiedApiMigration.migrate_assistants()

      assert result.failure == length(openai_assistants)
      assert result.success == 0

      assert Repo.aggregate(Assistant, :count, :id) == 0
      assert Repo.aggregate(AssistantConfigVersion, :count, :id) == 0
    end
  end

  # ---- Helper functions ----
  defp enable_kaapi(attrs) do
    {:ok, credential} =
      Partners.create_credential(%{
        organization_id: attrs.organization_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{"api_key" => "sk_3fa22108-f464-41e5-81d9-d8a298854430"},
        is_active: true
      })

    valid_update_attrs = %{
      keys: %{},
      secrets: %{"api_key" => "sk_3fa22108-f464-41e5-81d9-d8a298854430"},
      is_active: true,
      organization_id: attrs.organization_id,
      shortcode: "kaapi"
    }

    Partners.update_credential(credential, valid_update_attrs)
  end

  defp create_vector_store_with_assistant(organization_id, count) do
    for _ <- 1..count do
      organization_id
      |> create_vector_store()
      |> case do
        {:ok, vector_store} ->
          create_openai_assistant(organization_id, vector_store)
          {:ok, vector_store}

        error ->
          error
      end
    end
    |> Enum.filter(fn result -> elem(result, 0) == :ok end)
    |> Enum.map(&elem(&1, 1))
  end

  defp create_vector_store_without_assistant(organization_id, count) do
    for _ <- 1..count do
      create_vector_store(organization_id)
    end
    |> Enum.filter(fn result -> elem(result, 0) == :ok end)
    |> Enum.map(&elem(&1, 1))
  end

  defp create_vector_store(organization_id) do
    attrs = %{
      organization_id: organization_id,
      name: Faker.Person.first_name() <> "_" <> to_string(Faker.random_between(1, 100_000)),
      vector_store_id: Faker.UUID.v4(),
      files: %{"#{Faker.UUID.v4()}" => %{"file_name" => Faker.File.file_name()}},
      status: "in_progress",
      size: Faker.random_between(100, 1000)
    }

    %VectorStore{}
    |> VectorStore.changeset(attrs)
    |> Repo.insert()
  end

  defp update_vector_store(vector_store) do
    attrs = %{
      files: %{"#{Faker.UUID.v4()}" => %{"file_name" => Faker.File.file_name()}},
      status: "completed",
      size: Faker.random_between(100, 1000)
    }

    vector_store
    |> Changeset.change(attrs)
    |> Repo.update()
  end

  defp create_and_insert_vector_store(organization_id) do
    {:ok, vector_store} = create_vector_store(organization_id)
    vector_store
  end

  defp create_openai_assistants(organization_id, vector_store, count) do
    for _ <- 1..count do
      create_openai_assistant(organization_id, vector_store)
    end
  end

  defp create_openai_assistant(organization_id, vector_store, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          assistant_id: Faker.UUID.v4(),
          name: Faker.Person.first_name() <> "_" <> to_string(Faker.random_between(1, 100_000)),
          organization_id: organization_id,
          model: "gpt-4o",
          temperature: 1.0,
          instructions: "You are a helpful assistant",
          vector_store_id: vector_store && vector_store.id
        },
        overrides
      )

    {:ok, assistant} =
      %OpenAIAssistant{}
      |> OpenAIAssistant.changeset(attrs)
      |> Repo.insert()

    assistant
  end

  defp assert_assistant_migration(openai_assistant) do
    {:ok, assistant} =
      Repo.fetch_by(Assistant, %{
        name: openai_assistant.name,
        organization_id: openai_assistant.organization_id
      })

    assert assistant.assistant_display_id == openai_assistant.assistant_id
    refute is_nil(assistant.kaapi_uuid)
    assert {:ok, _} = Ecto.UUID.cast(assistant.kaapi_uuid)
    refute is_nil(assistant.active_config_version_id)

    {:ok, config_version} =
      Repo.fetch_by(AssistantConfigVersion, %{assistant_id: assistant.id})

    expected_prompt = openai_assistant.instructions || "You are a helpful assistant"
    expected_model = openai_assistant.model || "gpt-4o"
    expected_temperature = openai_assistant.temperature || 1
    expected_inserted_at = openai_assistant.inserted_at

    assert config_version.prompt == expected_prompt
    assert config_version.model == expected_model
    assert config_version.provider == "kaapi"
    assert config_version.settings["temperature"] == expected_temperature
    assert config_version.status == :ready
    assert config_version.inserted_at == expected_inserted_at
    assert assistant.active_config_version_id == config_version.id
  end

  defp assert_vector_migration(vector_store) do
    assert {:ok, knowledge_base} = Repo.fetch_by(KnowledgeBase, %{name: vector_store.name})

    {:ok, knowledge_base_version} =
      Repo.fetch_by(KnowledgeBaseVersion, %{llm_service_id: vector_store.vector_store_id})

    assert knowledge_base_version.status == :completed
    assert knowledge_base_version.version_number == 1
    assert knowledge_base_version.files == vector_store.files
    assert knowledge_base_version.size == vector_store.size
    assert knowledge_base_version.knowledge_base_id == knowledge_base.id
    refute knowledge_base_version.kaapi_job_id
  end
end
