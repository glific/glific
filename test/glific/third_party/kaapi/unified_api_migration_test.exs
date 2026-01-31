defmodule Glific.ThirdParty.Kaapi.UnifiedApiMigrationTest do
  alias Glific.Assistants.KnowledgeBase
  use Glific.DataCase

  alias Ecto.Changeset
  alias Glific.Assistants.KnowledgeBase
  alias Glific.Assistants.KnowledgeBaseVersion
  alias Glific.Filesearch.Assistant
  alias Glific.Filesearch.VectorStore
  alias Glific.ThirdParty.Kaapi.UnifiedApiMigration

  describe "migrate_vector_stores/0" do
    test "successfully migrates all vector stores with assistants", %{
      organization_id: organization_id
    } do
      vector_stores = create_vector_store_with_assistant(organization_id, 10)
      vector_stores_count = Enum.count(vector_stores)

      assert %{success: vector_stores_count, failure: 0} ==
               UnifiedApiMigration.migrate_vector_stores()

      assert Repo.aggregate(KnowledgeBase, :count, :id) == vector_stores_count
      assert Repo.aggregate(KnowledgeBaseVersion, :count, :id) == vector_stores_count

      for vector_store <- vector_stores do
        assert_vector_migration(vector_store)
      end
    end

    test "skips vector stores without assistants", %{organization_id: organization_id} do
      vector_stores = create_vector_store_with_assistant(organization_id, 10)
      vector_stores_without_assistants = create_vector_store_without_assistant(organization_id, 5)

      vector_stores_count = Enum.count(vector_stores)

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
      organization_id: organization_id
    } do
      vector_stores = create_vector_store_with_assistant(organization_id, 10)
      vector_stores_count = Enum.count(vector_stores)

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
  end

  # Helper functions
  defp create_vector_store_with_assistant(organization_id, count) do
    for _ <- 1..count do
      organization_id
      |> create_vector_store()
      |> case do
        {:ok, vector_store} ->
          create_assistant(vector_store)
          {:ok, vector_store}

        error ->
          error
      end
    end
    |> Enum.filter(fn vector_store -> elem(vector_store, 0) == :ok end)
    |> Enum.map(&elem(&1, 1))
  end

  defp create_vector_store_without_assistant(organization_id, count) do
    for _ <- 1..count do
      create_vector_store(organization_id)
    end
    |> Enum.filter(fn vector_store -> elem(vector_store, 0) == :ok end)
    |> Enum.map(&elem(&1, 1))
  end

  defp create_vector_store(organization_id) do
    Repo.insert(%VectorStore{
      organization_id: organization_id,
      name: Faker.Person.first_name(),
      vector_store_id: Faker.UUID.v4(),
      files: %{"#{Faker.UUID.v4()}" => %{"file_name" => Faker.File.file_name()}},
      status: "in_progress",
      size: Faker.random_between(100, 1000)
    })
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

  defp create_assistant(vector_store) do
    Repo.insert(%Assistant{
      assistant_id: Faker.UUID.v4(),
      name: Faker.Person.first_name(),
      organization_id: vector_store.organization_id,
      model: "gpt4o",
      temperature: Faker.random_uniform(),
      vector_store_id: vector_store.id
    })
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
