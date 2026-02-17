defmodule Glific.AssistantsTest do
  use Glific.DataCase
  import Tesla.Mock

  import Ecto.Query

  alias Glific.Assistants
  alias Glific.Assistants.Assistant
  alias Glific.Assistants.AssistantConfigVersion
  alias Glific.Assistants.KnowledgeBase
  alias Glific.Assistants.KnowledgeBaseVersion
  alias Glific.Notifications.Notification
  alias Glific.Partners
  alias Glific.Repo

  defp enable_kaapi(attrs) do
    {:ok, credential} =
      Partners.create_credential(%{
        organization_id: attrs.organization_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{
          "api_key" => "sk_3fa22108-f464-41e5-81d9-d8a298854430"
        }
      })

    valid_update_attrs = %{
      keys: %{},
      secrets: %{
        "api_key" => "sk_3fa22108-f464-41e5-81d9-d8a298854430"
      },
      is_active: true,
      organization_id: attrs.organization_id,
      shortcode: "kaapi"
    }

    Partners.update_credential(credential, valid_update_attrs)
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

  describe "process_timeouts/1" do
    setup %{organization_id: org_id} do
      {knowledge_base, knowledge_base_version} =
        create_knowledge_base_version(org_id, :in_progress, "job_123", hours_ago: 2)

      {assistant, config_version} = create_assistant_with_config(org_id, :in_progress)
      link_kbv_to_acv(knowledge_base_version, config_version, org_id)

      [
        knowledge_base: knowledge_base,
        knowledge_base_version: knowledge_base_version,
        assistant: assistant,
        config_version: config_version
      ]
    end

    test "marks timed-out KnowledgeBaseVersion as failed", %{
      organization_id: org_id,
      knowledge_base_version: knowledge_base_version
    } do
      assert :ok = Assistants.process_timeouts(org_id)

      {:ok, updated_kbv} = Repo.fetch_by(KnowledgeBaseVersion, %{id: knowledge_base_version.id})
      assert updated_kbv.status == :failed
    end

    test "does NOT affect records less than 1 hour old", %{organization_id: org_id} do
      {_knowledge_base, knowledge_base_version} =
        create_knowledge_base_version(org_id, :in_progress, "job_456", hours_ago: 0)

      assert :ok = Assistants.process_timeouts(org_id)

      {:ok, updated_kbv} =
        Repo.fetch_by(KnowledgeBaseVersion, %{id: knowledge_base_version.id})

      assert updated_kbv.status == :in_progress
    end

    test "ignores records that are already completed", %{organization_id: org_id} do
      {_knowledge_base, knowledge_base_version} =
        create_knowledge_base_version(org_id, :completed, "job_456", hours_ago: 2)

      assert :ok = Assistants.process_timeouts(org_id)

      {:ok, updated_kbv} =
        Repo.fetch_by(KnowledgeBaseVersion, %{id: knowledge_base_version.id})

      assert updated_kbv.status == :completed
    end

    test "updates linked in_progress AssistantConfigVersions to failed", %{
      organization_id: org_id,
      config_version: config_version
    } do
      assert :ok = Assistants.process_timeouts(org_id)

      {:ok, updated_acv} = Repo.fetch_by(AssistantConfigVersion, %{id: config_version.id})
      assert updated_acv.status == :failed
      assert updated_acv.failure_reason =~ "vector store creation timed out"
    end

    test "creates notification with correct details", %{
      organization_id: org_id,
      knowledge_base: knowledge_base,
      knowledge_base_version: knowledge_base_version,
      assistant: assistant,
      config_version: config_version
    } do
      initial_count = Repo.aggregate(Notification, :count, :id)

      assert :ok = Assistants.process_timeouts(org_id)

      assert Repo.aggregate(Notification, :count, :id) == initial_count + 1

      notification =
        Notification
        |> where([n], n.organization_id == ^org_id)
        |> order_by([n], desc: n.inserted_at)
        |> limit(1)
        |> Repo.one()

      assert notification.category == "Assistant"
      assert notification.severity == "Warning"
      assert notification.message == "Knowledge Base creation timeout"
      assert notification.entity["knowledge_base_version_id"] == knowledge_base_version.id
      assert notification.entity["knowledge_base_name"] == knowledge_base.name
      assert notification.entity["affected_config_version_ids"] == [config_version.id]
      assert assistant.name in notification.entity["affected_assistant_names"]
    end

    test "processes multiple timed-out records", %{
      organization_id: org_id,
      knowledge_base_version: knowledge_base_version_1
    } do
      {_knowledge_base_2, knowledge_base_version_2} =
        create_knowledge_base_version(org_id, :in_progress, "job_2", hours_ago: 3)

      assert :ok = Assistants.process_timeouts(org_id)

      {:ok, updated_kbv_1} =
        Repo.fetch_by(KnowledgeBaseVersion, %{id: knowledge_base_version_1.id})

      {:ok, updated_kbv_2} =
        Repo.fetch_by(KnowledgeBaseVersion, %{id: knowledge_base_version_2.id})

      assert updated_kbv_1.status == :failed
      assert updated_kbv_2.status == :failed
    end
  end

  defp create_knowledge_base_version(org_id, status, kaapi_job_id, opts) do
    hours_ago = Keyword.get(opts, :hours_ago, 0)

    {:ok, knowledge_base} =
      %KnowledgeBase{}
      |> KnowledgeBase.changeset(%{
        name: "Test Knowledge Base #{:rand.uniform(10000)}",
        organization_id: org_id
      })
      |> Repo.insert()

    {:ok, knowledge_base_version} =
      %KnowledgeBaseVersion{}
      |> KnowledgeBaseVersion.changeset(%{
        knowledge_base_id: knowledge_base.id,
        organization_id: org_id,
        files: %{"file1.pdf" => %{"size" => 1024}},
        status: status,
        llm_service_id: "vs_test_#{:rand.uniform(10000)}",
        kaapi_job_id: kaapi_job_id
      })
      |> Repo.insert()

    if hours_ago > 0 do
      past_time = DateTime.utc_now() |> DateTime.add(-hours_ago, :hour)

      KnowledgeBaseVersion
      |> where([kbv], kbv.id == ^knowledge_base_version.id)
      |> Repo.update_all(set: [inserted_at: past_time])
    end

    {:ok, refreshed} = Repo.fetch_by(KnowledgeBaseVersion, %{id: knowledge_base_version.id})
    {knowledge_base, refreshed}
  end

  defp create_assistant_with_config(org_id, status) do
    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{
        name: "Test Assistant #{:rand.uniform(10000)}",
        organization_id: org_id,
        kaapi_uuid: "asst_#{:rand.uniform(10000)}"
      })
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        organization_id: org_id,
        provider: "openai",
        model: "gpt-4o",
        prompt: "You are a helpful assistant",
        kaapi_uuid: "acv_#{:rand.uniform(10000)}",
        settings: %{"temperature" => 1.0},
        status: status
      })
      |> Repo.insert()

    {assistant, config_version}
  end

  defp link_kbv_to_acv(knowledge_base_version, config_version, org_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all("assistant_config_version_knowledge_base_versions", [
      %{
        assistant_config_version_id: config_version.id,
        knowledge_base_version_id: knowledge_base_version.id,
        organization_id: org_id,
        inserted_at: now,
        updated_at: now
      }
    ])
  end

  describe "delete_assistant/1" do
    test "deletes assistant with kaapi_uuid after deleting config and assistant from kaapi",
         %{organization_id: organization_id} do
      enable_kaapi(%{organization_id: organization_id})
      {assistant, config_version} = create_assistant_with_config(organization_id, :ready)

      mock(fn %Tesla.Env{method: :delete} ->
        %Tesla.Env{
          status: 200,
          body: %{error: nil, data: "Deleted", metadata: nil, success: true}
        }
      end)

      assert {:ok, %Assistant{}} = Assistants.delete_assistant(assistant.id)
      assert {:error, _} = Repo.fetch(Assistant, assistant.id, skip_organization_id: true)

      assert {:error, _} =
               Repo.fetch(AssistantConfigVersion, config_version.id, skip_organization_id: true)
    end

    test "returns error when assistant not found" do
      assert {:error, _} = Assistants.delete_assistant(-1)
    end

    test "returns error when kaapi delete fails",
         %{organization_id: organization_id} do
      enable_kaapi(%{organization_id: organization_id})
      {assistant, _config_version} = create_assistant_with_config(organization_id, :ready)

      mock(fn %Tesla.Env{method: :delete} ->
        %Tesla.Env{status: 500, body: %{error: "Internal Server Error"}}
      end)

      assert {:error, _} = Assistants.delete_assistant(assistant.id)
      # assistant should still exist
      assert {:ok, _} = Repo.fetch(Assistant, assistant.id, skip_organization_id: true)
    end
  end
end
