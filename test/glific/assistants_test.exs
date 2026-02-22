defmodule Glific.AssistantsTest do
  use Glific.DataCase

  import Ecto.Query

  alias Glific.Assistants
  alias Glific.Assistants.Assistant
  alias Glific.Assistants.AssistantConfigVersion
  alias Glific.Assistants.KnowledgeBase
  alias Glific.Assistants.KnowledgeBaseVersion
  alias Glific.Notifications.Notification
  alias Glific.Partners
  alias Glific.Repo

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

  describe "update_assistant_version/2" do
    setup %{organization_id: organization_id} do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{name: "Test Assistant", organization_id: organization_id})
        |> Repo.insert()

      {:ok, assistant_version} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4",
          prompt: "You are a helpful assistant",
          settings: %{"temperature" => 0.7},
          status: :in_progress
        })
        |> Repo.insert()

      %{assistant_version: assistant_version}
    end

    test "updates with valid attrs", %{assistant_version: av} do
      assert {:ok, %AssistantConfigVersion{} = updated} =
               Assistants.update_assistant_version(av, %{
                 status: :failed,
                 description: "Updated description",
                 prompt: "New system prompt",
                 failure_reason: "Kaapi API error",
                 model: "gpt-4o",
                 settings: %{"temperature" => 0.5}
               })

      assert updated.description == "Updated description"
      assert updated.prompt == "New system prompt"
      assert updated.status == :failed
      assert updated.failure_reason == "Kaapi API error"
      assert updated.model == "gpt-4o"
      assert updated.settings == %{"temperature" => 0.5}
    end

    test "returns error with invalid attrs", %{assistant_version: av} do
      assert {:error, changeset} =
               Assistants.update_assistant_version(av, %{status: :invalid, prompt: nil})

      assert %{status: ["is invalid"], prompt: ["can't be blank"]} == errors_on(changeset)
    end

    test "preserves unchanged fields after update", %{assistant_version: av} do
      assert {:ok, %AssistantConfigVersion{} = updated} =
               Assistants.update_assistant_version(av, %{status: :ready})

      assert updated.prompt == av.prompt
      assert updated.provider == av.provider
      assert updated.model == av.model
      assert updated.settings == av.settings
      assert updated.assistant_id == av.assistant_id
      assert updated.organization_id == av.organization_id
    end
  end

  describe "create_knowledge_base_with_version/1" do
    setup :enable_kaapi

    test "creates knowledge base and version, and sets kaapi_job_id",
         %{organization_id: organization_id} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{data: %{job_id: "job_abc123"}}
          }
      end)

      params = %{
        media_info: [
          %{file_id: "file_abc", filename: "doc.pdf", uploaded_at: DateTime.utc_now()},
          %{file_id: "file_xyz", filename: "notes.txt", uploaded_at: DateTime.utc_now()}
        ],
        organization_id: organization_id
      }

      assert {:ok,
              %{
                knowledge_base: %KnowledgeBase{} = knowledge_base,
                knowledge_base_version: %KnowledgeBaseVersion{} = knowledge_base_version
              }} = Assistants.create_knowledge_base_with_version(params)

      assert knowledge_base.organization_id == organization_id
      assert String.starts_with?(knowledge_base.name, "VectorStore-")

      assert knowledge_base_version.knowledge_base_id == knowledge_base.id
      assert knowledge_base_version.organization_id == organization_id
      assert knowledge_base_version.status == :in_progress
      assert knowledge_base_version.kaapi_job_id == "job_abc123"
      assert map_size(knowledge_base_version.files) == 2
      assert Map.has_key?(knowledge_base_version.files, "file_abc")
      assert Map.has_key?(knowledge_base_version.files, "file_xyz")
      assert String.starts_with?(knowledge_base_version.llm_service_id, "temporary-vs-")
    end

    test "uses existing knowledge base when id is provided",
         %{organization_id: organization_id} do
      {:ok, existing_knowledge_base} =
        Assistants.create_knowledge_base(%{
          name: "Existing KB",
          organization_id: organization_id
        })

      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{data: %{job_id: "job_def456"}}
          }
      end)

      params = %{
        id: existing_knowledge_base.id,
        media_info: [
          %{file_id: "file_new", filename: "report.pdf", uploaded_at: DateTime.utc_now()}
        ],
        organization_id: organization_id
      }

      assert {:ok,
              %{
                knowledge_base: %KnowledgeBase{} = knowledge_base,
                knowledge_base_version: %KnowledgeBaseVersion{} = knowledge_base_version
              }} = Assistants.create_knowledge_base_with_version(params)

      assert knowledge_base.id == existing_knowledge_base.id
      assert knowledge_base.name == "Existing KB"
      assert knowledge_base_version.knowledge_base_id == existing_knowledge_base.id
      assert knowledge_base_version.kaapi_job_id == "job_def456"
      assert knowledge_base_version.status == :in_progress
      assert map_size(knowledge_base_version.files) == 1
      assert Map.has_key?(knowledge_base_version.files, "file_new")
      assert String.starts_with?(knowledge_base_version.llm_service_id, "temporary-vs-")
    end

    test "returns error when kaapi api fails", %{organization_id: organization_id} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 500,
            body: %{error: "Internal server error"}
          }
      end)

      params = %{
        media_info: [%{file_id: "file_abc", filename: "doc.pdf", uploaded_at: DateTime.utc_now()}],
        organization_id: organization_id
      }

      assert {:error, "Failed to create knowledge base"} =
               Assistants.create_knowledge_base_with_version(params)
    end

    test "returns error when knowledge base id does not exist",
         %{organization_id: organization_id} do
      params = %{
        id: 0,
        media_info: [%{file_id: "file_abc", filename: "doc.pdf", uploaded_at: DateTime.utc_now()}],
        organization_id: organization_id
      }

      assert {:error, _} = Assistants.create_knowledge_base_with_version(params)
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

  defp enable_kaapi(%{organization_id: organization_id}) do
    Partners.create_credential(%{
      organization_id: organization_id,
      shortcode: "kaapi",
      keys: %{},
      secrets: %{
        "api_key" => "sk_3fa22108-f464-41e5-81d9-d8a298854430"
      },
      is_active: true
    })

    :ok
  end
end
