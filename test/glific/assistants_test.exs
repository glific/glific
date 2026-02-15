defmodule Glific.AssistantsTest do
  use Glific.DataCase

  alias Glific.Assistants
  alias Glific.Assistants.KnowledgeBase
  alias Glific.Assistants.KnowledgeBaseVersion

  describe "create_knowledge_base/1" do
    test "creates a knowledge base with valid attrs", %{organization_id: organization_id} do
      attrs = %{name: "Test Knowledge Base", organization_id: organization_id}

      assert {:ok, %KnowledgeBase{} = knowledge_base} = Assistants.create_knowledge_base(attrs)
      assert knowledge_base.name == "Test Knowledge Base"
      assert knowledge_base.organization_id == organization_id
    end

    test "returns error with invalid attrs", %{organization_id: organization_id} do
      attrs = %{name: "", organization_id: organization_id}

      assert {:error, changeset} = Assistants.create_knowledge_base(attrs)
      assert %{name: ["can't be blank"]} == errors_on(changeset)
    end
  end

  describe "create_knowledge_base_version/1" do
    test "creates a knowledge base version with valid attrs", %{organization_id: organization_id} do
      {:ok, knowledge_base} =
        Assistants.create_knowledge_base(%{
          name: "Test Knowledge Base",
          organization_id: organization_id
        })

      attrs = %{
        knowledge_base_id: knowledge_base.id,
        organization_id: organization_id,
        files: %{"file_123" => %{"name" => "test_file.txt"}},
        status: :in_progress,
        llm_service_id: "vs_12345",
        size: 100,
        version_number: 19
      }

      assert {:ok, %KnowledgeBaseVersion{} = knowledge_base_version} =
               Assistants.create_knowledge_base_version(attrs)

      assert knowledge_base_version.knowledge_base_id == knowledge_base.id
      assert knowledge_base_version.organization_id == organization_id
      assert knowledge_base_version.files == %{"file_123" => %{"name" => "test_file.txt"}}
      assert knowledge_base_version.status == :in_progress
      assert knowledge_base_version.llm_service_id == "vs_12345"
      assert knowledge_base_version.size == 100
      assert knowledge_base_version.version_number == 19
    end

    test "auto increments version number", %{organization_id: organization_id} do
      {:ok, knowledge_base} =
        Assistants.create_knowledge_base(%{
          name: "Test Knowledge Base",
          organization_id: organization_id
        })

      attrs = %{
        knowledge_base_id: knowledge_base.id,
        organization_id: organization_id,
        files: %{"file_123" => %{"name" => "test_file.txt"}},
        status: :in_progress,
        llm_service_id: "vs_12345",
        size: 100,
        version_number: 19
      }

      assert {:ok, %KnowledgeBaseVersion{} = knowledge_base_version} =
               Assistants.create_knowledge_base_version(attrs)

      assert knowledge_base_version.version_number == 19

      attrs = %{
        knowledge_base_id: knowledge_base.id,
        organization_id: organization_id,
        files: %{
          "file_123" => %{"name" => "test_file.txt"},
          "file_456" => %{"name" => "new_file.txt"}
        },
        status: :completed,
        llm_service_id: "vs_67890",
        size: 200
      }

      assert {:ok, %KnowledgeBaseVersion{} = knowledge_base_version} =
               Assistants.create_knowledge_base_version(attrs)

      # Since we use a trigger to increment the version number, we need to fetch the updated version
      {:ok, knowledge_base_version} =
        Repo.fetch(KnowledgeBaseVersion, knowledge_base_version.id, skip_organization_id: true)

      assert knowledge_base_version.version_number == 20
    end

    test "returns error with invalid attrs", %{organization_id: organization_id} do
      {:ok, knowledge_base} =
        Assistants.create_knowledge_base(%{
          name: "Test Knowledge Base",
          organization_id: organization_id
        })

      attrs = %{
        llm_service_id: nil,
        knowledge_base_id: knowledge_base.id,
        organization_id: organization_id,
        files: %{},
        status: :in_progress,
        size: 100
      }

      assert {:error, changeset} = Assistants.create_knowledge_base_version(attrs)
      assert %{llm_service_id: ["can't be blank"]} == errors_on(changeset)
    end
  end

  describe "update_knowledge_base_version/2" do
    setup %{organization_id: organization_id} do
      {:ok, knowledge_base} =
        Assistants.create_knowledge_base(%{
          name: "Test Knowledge Base",
          organization_id: organization_id
        })

      {:ok, knowledge_base_version} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: knowledge_base.id,
          organization_id: organization_id,
          files: %{"file_123" => %{"name" => "test_file.txt"}},
          status: :in_progress,
          llm_service_id: "vs_12345",
          size: 100
        })

      %{knowledge_base_version: knowledge_base_version}
    end

    test "updates with valid attrs", %{knowledge_base_version: kbv} do
      assert {:ok, %KnowledgeBaseVersion{} = updated} =
               Assistants.update_knowledge_base_version(kbv, %{
                 status: :completed,
                 kaapi_job_id: "job_xyz",
                 llm_service_id: "vs_updated",
                 size: 250
               })

      assert updated.status == :completed
      assert updated.kaapi_job_id == "job_xyz"
      assert updated.llm_service_id == "vs_updated"
      assert updated.size == 250
    end

    test "returns error with invalid attrs", %{knowledge_base_version: kbv} do
      assert {:error, changeset} =
               Assistants.update_knowledge_base_version(kbv, %{
                 llm_service_id: nil,
                 status: :ready
               })

      assert %{llm_service_id: ["can't be blank"], status: ["is invalid"]} == errors_on(changeset)
    end

    test "preserves unchanged fields after update", %{knowledge_base_version: kbv} do
      assert {:ok, %KnowledgeBaseVersion{} = updated} =
               Assistants.update_knowledge_base_version(kbv, %{status: :completed})

      assert updated.llm_service_id == kbv.llm_service_id
      assert updated.files == kbv.files
      assert updated.size == kbv.size
      assert updated.knowledge_base_id == kbv.knowledge_base_id
      assert updated.organization_id == kbv.organization_id
    end
  end
end
