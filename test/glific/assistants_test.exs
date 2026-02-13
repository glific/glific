defmodule Glific.AssistantsTest do
  use Glific.DataCase
  import Tesla.Mock

  alias Glific.{
    Assistants,
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Assistants.KnowledgeBase,
    Assistants.KnowledgeBaseVersion,
    Partners,
    Repo
  }

  defp create_assistant(organization_id) do
    %Assistant{}
    |> Assistant.changeset(%{
      name: "Test Assistant",
      organization_id: organization_id
    })
    |> Repo.insert!()
  end

  defp create_config_version(assistant_id, organization_id, kaapi_uuid) do
    %AssistantConfigVersion{}
    |> AssistantConfigVersion.changeset(%{
      assistant_id: assistant_id,
      prompt: "You are a helpful assistant",
      provider: "openai",
      model: "gpt-4o",
      kaapi_uuid: kaapi_uuid,
      settings: %{"temperature" => 0.7},
      status: :ready,
      organization_id: organization_id
    })
    |> Repo.insert!()
  end

  defp enable_kaapi(organization_id) do
    {:ok, credential} =
      Partners.create_credential(%{
        organization_id: organization_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{
          "api_key" => "sk_3fa22108-f464-41e5-81d9-d8a298854430"
        }
      })

    Partners.update_credential(credential, %{
      keys: %{},
      secrets: %{"api_key" => "api-key-12345"},
      is_active: true,
      organization_id: organization_id,
      shortcode: "kaapi"
    })
  end

  describe "delete_assistant/2" do
    test "deletes assistant with config versions after deleting config from kaapi",
         %{organization_id: organization_id} do
      enable_kaapi(organization_id)
      assistant = create_assistant(organization_id)
      create_config_version(assistant.id, organization_id, "kaapi-uuid-123")

      mock(fn %Tesla.Env{method: :delete} ->
        %Tesla.Env{
          status: 200,
          body: %{error: nil, data: "Deleted", metadata: nil, success: true}
        }
      end)

      assert {:ok, %Assistant{}} = Assistants.delete_assistant(assistant.id)
      assert {:error, _} = Repo.fetch(Assistant, assistant.id, skip_organization_id: true)
    end

    test "deletes assistant without config versions (no kaapi call)",
         %{organization_id: organization_id} do
      assistant = create_assistant(organization_id)

      assert {:ok, %Assistant{}} = Assistants.delete_assistant(assistant.id)
      assert {:error, _} = Repo.fetch(Assistant, assistant.id, skip_organization_id: true)
    end

    test "returns error when assistant not found" do
      assert {:error, _} = Assistants.delete_assistant(-1)
    end

    test "returns error when kaapi delete fails",
         %{organization_id: organization_id} do
      enable_kaapi(organization_id)
      assistant = create_assistant(organization_id)
      create_config_version(assistant.id, organization_id, "kaapi-uuid-456")

      mock(fn %Tesla.Env{method: :delete} ->
        %Tesla.Env{status: 500, body: %{error: "Internal Server Error"}}
      end)

      assert {:error, _} = Assistants.delete_assistant(assistant.id)
      # assistant should still exist
      assert {:ok, _} = Repo.fetch(Assistant, assistant.id, skip_organization_id: true)
    end
  end

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
end
