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
          "api_key" => "sk_test_key"
        }
      })

    valid_update_attrs = %{
      keys: %{},
      secrets: %{
        "api_key" => "sk_test_key"
      },
      is_active: true,
      organization_id: attrs.organization_id,
      shortcode: "kaapi"
    }

    {:ok, _credential} = Partners.update_credential(credential, valid_update_attrs)
    :ok
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

    test "cleans up newly created KnowledgeBase and KnowledgeBaseVersion when Kaapi fails",
         %{organization_id: organization_id} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 500,
            body: %{error: "Internal server error"}
          }
      end)

      kb_count_before = Repo.aggregate(KnowledgeBase, :count, :id)
      kbv_count_before = Repo.aggregate(KnowledgeBaseVersion, :count, :id)

      params = %{
        media_info: [%{file_id: "file_abc", filename: "doc.pdf", uploaded_at: DateTime.utc_now()}],
        organization_id: organization_id
      }

      assert {:error, "Failed to create knowledge base"} =
               Assistants.create_knowledge_base_with_version(params)

      # Both newly created records should have been cleaned up
      assert Repo.aggregate(KnowledgeBase, :count, :id) == kb_count_before
      assert Repo.aggregate(KnowledgeBaseVersion, :count, :id) == kbv_count_before
    end

    test "cleans up KnowledgeBaseVersion but NOT existing KnowledgeBase when Kaapi fails",
         %{organization_id: organization_id} do
      {:ok, existing_knowledge_base} =
        Assistants.create_knowledge_base(%{
          name: "Existing KB",
          organization_id: organization_id
        })

      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 500,
            body: %{error: "Internal server error"}
          }
      end)

      kbv_count_before = Repo.aggregate(KnowledgeBaseVersion, :count, :id)

      params = %{
        id: existing_knowledge_base.id,
        media_info: [%{file_id: "file_abc", filename: "doc.pdf", uploaded_at: DateTime.utc_now()}],
        organization_id: organization_id
      }

      assert {:error, "Failed to create knowledge base"} =
               Assistants.create_knowledge_base_with_version(params)

      # The existing KnowledgeBase should NOT be deleted
      assert {:ok, _} =
               Repo.fetch(KnowledgeBase, existing_knowledge_base.id, skip_organization_id: true)

      # The newly created KnowledgeBaseVersion should be cleaned up
      assert Repo.aggregate(KnowledgeBaseVersion, :count, :id) == kbv_count_before
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

  describe "update_assistant/2" do
    setup [:enable_kaapi, :setup_assistant_with_kb]

    test "returns current assistant without creating a new config version when nothing changes",
         %{organization_id: organization_id, assistant: assistant, config_version: config_version} do
      initial_config_count =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> Repo.aggregate(:count, :id)

      assert {:ok, result} =
               Assistants.update_assistant(assistant.id, %{
                 name: assistant.name,
                 instructions: config_version.prompt,
                 model: config_version.model,
                 temperature: get_in(config_version.settings, ["temperature"]),
                 organization_id: organization_id
               })

      final_config_count =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> Repo.aggregate(:count, :id)

      assert result.name == assistant.name
      assert initial_config_count == final_config_count
    end

    test "creates a new config version and updates the assistant when name changes",
         %{organization_id: organization_id, assistant: assistant} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{id: "new_kaapi_uuid_abc", version: 2}}}
      end)

      assert {:ok, result} =
               Assistants.update_assistant(assistant.id, %{
                 name: "Updated Name",
                 organization_id: organization_id
               })

      assert result.name == "Updated Name"

      config_count =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> Repo.aggregate(:count, :id)

      assert config_count == 2

      {:ok, updated_assistant} =
        Repo.fetch(Assistant, assistant.id, skip_organization_id: true)

      updated_assistant = Repo.preload(updated_assistant, :active_config_version)
      assert updated_assistant.active_config_version.kaapi_version_number == 2
    end

    test "creates a new config version when temperature changes",
         %{organization_id: organization_id, assistant: assistant} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{id: "new_kaapi_uuid_temp", version: 2}}}
      end)

      assert {:ok, result} =
               Assistants.update_assistant(assistant.id, %{
                 temperature: 0.5,
                 organization_id: organization_id
               })

      assert result.temperature == 0.5

      config_count =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> Repo.aggregate(:count, :id)

      assert config_count == 2
    end

    test "creates a new config version when model changes",
         %{organization_id: organization_id, assistant: assistant} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{id: "new_kaapi_uuid_model", version: 2}}}
      end)

      assert {:ok, result} =
               Assistants.update_assistant(assistant.id, %{
                 model: "gpt-4o-mini",
                 organization_id: organization_id
               })

      assert result.model == "gpt-4o-mini"

      config_count =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> Repo.aggregate(:count, :id)

      assert config_count == 2
    end

    test "creates a new config version when instructions change",
         %{organization_id: organization_id, assistant: assistant} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{id: "new_kaapi_uuid_instructions", version: 2}}}
      end)

      assert {:ok, result} =
               Assistants.update_assistant(assistant.id, %{
                 instructions: "You are a specialized assistant",
                 organization_id: organization_id
               })

      assert result.instructions == "You are a specialized assistant"

      config_count =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> Repo.aggregate(:count, :id)

      assert config_count == 2
    end

    test "creates a new config version when knowledge base changes",
         %{organization_id: organization_id, assistant: assistant} do
      {:ok, new_kb} =
        Assistants.create_knowledge_base(%{
          name: "New KB",
          organization_id: organization_id
        })

      {:ok, _new_kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: new_kb.id,
          organization_id: organization_id,
          files: %{"file_2" => %{"filename" => "new_doc.pdf"}},
          status: :completed,
          llm_service_id: "vs_new_456",
          size: 200
        })

      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{id: "new_kaapi_uuid_kb", version: 2}}}
      end)

      assert {:ok, _result} =
               Assistants.update_assistant(assistant.id, %{
                 knowledge_base_id: new_kb.id,
                 organization_id: organization_id
               })

      config_count =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> Repo.aggregate(:count, :id)

      assert config_count == 2
    end

    test "returns error when assistant does not exist", %{organization_id: organization_id} do
      assert {:error, _} = Assistants.update_assistant(0, %{organization_id: organization_id})
    end

    test "no-op returns correct config field values",
         %{
           organization_id: organization_id,
           assistant: assistant,
           config_version: config_version
         } do
      assert {:ok, result} =
               Assistants.update_assistant(assistant.id, %{
                 name: assistant.name,
                 instructions: config_version.prompt,
                 model: config_version.model,
                 temperature: get_in(config_version.settings, ["temperature"]),
                 organization_id: organization_id
               })

      assert result.model == config_version.model
      assert result.instructions == config_version.prompt
      assert result.temperature == get_in(config_version.settings, ["temperature"])
    end

    test "new config version persists the updated temperature value",
         %{organization_id: organization_id, assistant: assistant} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{id: "new_kaapi_uuid_temp2", version: 2}}}
      end)

      assert {:ok, _result} =
               Assistants.update_assistant(assistant.id, %{
                 temperature: 0.3,
                 organization_id: organization_id
               })

      new_config =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> order_by([acv], desc: acv.id)
        |> limit(1)
        |> Repo.one()

      assert get_in(new_config.settings, ["temperature"]) == 0.3
    end

    test "new config version persists the updated model value",
         %{organization_id: organization_id, assistant: assistant} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{id: "new_kaapi_uuid_model2", version: 2}}}
      end)

      assert {:ok, _result} =
               Assistants.update_assistant(assistant.id, %{
                 model: "gpt-4o-mini",
                 organization_id: organization_id
               })

      new_config =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> order_by([acv], desc: acv.id)
        |> limit(1)
        |> Repo.one()

      assert new_config.model == "gpt-4o-mini"
    end

    test "new config version persists the updated instructions value",
         %{organization_id: organization_id, assistant: assistant} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{data: %{id: "new_kaapi_uuid_instructions2", version: 2}}
          }
      end)

      assert {:ok, _result} =
               Assistants.update_assistant(assistant.id, %{
                 instructions: "You are a specialized assistant",
                 organization_id: organization_id
               })

      new_config =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> order_by([acv], desc: acv.id)
        |> limit(1)
        |> Repo.one()

      assert new_config.prompt == "You are a specialized assistant"
    end

    test "multiple fields changing creates only one new config version",
         %{organization_id: organization_id, assistant: assistant} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{id: "new_kaapi_uuid_multi", version: 2}}}
      end)

      assert {:ok, result} =
               Assistants.update_assistant(assistant.id, %{
                 name: "Multi-Update Name",
                 model: "gpt-4o-mini",
                 temperature: 0.7,
                 organization_id: organization_id
               })

      assert result.name == "Multi-Update Name"
      assert result.model == "gpt-4o-mini"
      assert result.temperature == 0.7

      config_count =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> Repo.aggregate(:count, :id)

      assert config_count == 2
    end

    test "returns error when Kaapi API call fails",
         %{organization_id: organization_id, assistant: assistant} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 500, body: %{error: "Internal server error"}}
      end)

      assert {:error, _} =
               Assistants.update_assistant(assistant.id, %{
                 name: "Updated Name",
                 organization_id: organization_id
               })
    end
  end

  describe "update_assistant/2 with no existing knowledge base" do
    setup [:enable_kaapi]

    setup %{organization_id: organization_id} do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Test Assistant",
          organization_id: organization_id,
          kaapi_uuid: "test_kaapi_uuid"
        })
        |> Repo.insert()

      {:ok, config_version} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "You are a helpful assistant",
          settings: %{"temperature" => 1.0},
          status: :ready
        })
        |> Repo.insert()

      {:ok, assistant} =
        assistant
        |> Assistant.set_active_config_version_changeset(%{
          active_config_version_id: config_version.id
        })
        |> Repo.update()

      # Create a KB version NOT linked to the assistant
      {:ok, kb} =
        Assistants.create_knowledge_base(%{
          name: "Unlinked KB",
          organization_id: organization_id
        })

      {:ok, kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: kb.id,
          organization_id: organization_id,
          files: %{"file_1" => %{"filename" => "doc.pdf"}},
          status: :completed,
          llm_service_id: "vs_unlinked_123",
          size: 500
        })

      Partners.organization(organization_id)

      %{assistant: assistant, config_version: config_version, knowledge_base_version: kbv}
    end

    test "links knowledge base when updating assistant with no existing KB",
         %{
           organization_id: organization_id,
           assistant: assistant,
           config_version: config_version,
           knowledge_base_version: kbv
         } do
      # Verify no bridge entry exists before update
      bridge_count_before =
        "assistant_config_version_knowledge_base_versions"
        |> where([b], b.assistant_config_version_id == ^config_version.id)
        |> Repo.aggregate(:count, :id)

      assert bridge_count_before == 0

      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{id: "new_kaapi_uuid_link_kb", version: 2}}}
      end)

      assert {:ok, _result} =
               Assistants.update_assistant(assistant.id, %{
                 name: assistant.name,
                 instructions: config_version.prompt,
                 model: config_version.model,
                 temperature: get_in(config_version.settings, ["temperature"]),
                 knowledge_base_version_id: kbv.id,
                 organization_id: organization_id
               })

      # Verify bridge entry was created for the active config version
      bridge_count_after =
        "assistant_config_version_knowledge_base_versions"
        |> where([b], b.assistant_config_version_id == ^config_version.id)
        |> Repo.aggregate(:count, :id)

      assert bridge_count_after == 1

      # Verify a new config version was also created
      config_count =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> Repo.aggregate(:count, :id)

      assert config_count == 2
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

  defp setup_assistant_with_kb(%{organization_id: organization_id}) do
    {:ok, kb} =
      Assistants.create_knowledge_base(%{
        name: "Test KB",
        organization_id: organization_id
      })

    {:ok, kbv} =
      Assistants.create_knowledge_base_version(%{
        knowledge_base_id: kb.id,
        organization_id: organization_id,
        files: %{"file_1" => %{"filename" => "doc.pdf"}},
        status: :completed,
        llm_service_id: "vs_test_123",
        size: 500
      })

    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{
        name: "Test Assistant",
        organization_id: organization_id,
        kaapi_uuid: "test_kaapi_uuid"
      })
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        organization_id: organization_id,
        provider: "openai",
        model: "gpt-4o",
        prompt: "You are a helpful assistant",
        settings: %{"temperature" => 1.0},
        status: :ready
      })
      |> Repo.insert()

    link_kbv_to_acv(kbv, config_version, organization_id)

    {:ok, assistant} =
      assistant
      |> Assistant.set_active_config_version_changeset(%{
        active_config_version_id: config_version.id
      })
      |> Repo.update()

    Partners.organization(organization_id)

    %{assistant: assistant, config_version: config_version, knowledge_base_version: kbv}
  end

  describe "create_assistant/1" do
    test "creates assistant and config version with nil kaapi_uuid",
         %{organization_id: organization_id} do
      {:ok, kb} =
        Assistants.create_knowledge_base(%{
          name: "Test KB",
          organization_id: organization_id
        })

      {:ok, kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: kb.id,
          organization_id: organization_id,
          files: %{},
          status: :in_progress,
          llm_service_id: "vs_test_123",
          size: 0
        })

      assert {:ok, %{assistant: assistant, config_version: config_version}} =
               Assistants.create_assistant(%{
                 name: "New Assistant",
                 model: "gpt-4o",
                 instructions: "You are a helpful assistant",
                 temperature: 1.0,
                 knowledge_base_version_id: kbv.id,
                 organization_id: organization_id
               })

      assert is_nil(assistant.kaapi_uuid)
      assert assistant.name == "New Assistant"
      assert assistant.active_config_version_id == config_version.id
      assert config_version.model == "gpt-4o"
      assert config_version.prompt == "You are a helpful assistant"

      config_version = Repo.preload(config_version, :knowledge_base_versions)
      assert length(config_version.knowledge_base_versions) == 1
    end

    test "creates assistant with in-progress KB and sets config status to in_progress",
         %{organization_id: organization_id} do
      {:ok, kb} =
        Assistants.create_knowledge_base(%{
          name: "In-Progress KB",
          organization_id: organization_id
        })

      {:ok, kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: kb.id,
          organization_id: organization_id,
          files: %{"file_1" => %{"filename" => "doc.pdf"}},
          status: :in_progress,
          llm_service_id: "temporary-vs-abc123",
          size: 500
        })

      assert {:ok, %{assistant: assistant, config_version: config_version}} =
               Assistants.create_assistant(%{
                 name: "Deferred Assistant",
                 model: "gpt-4o",
                 instructions: "You are a helpful assistant",
                 temperature: 1.0,
                 knowledge_base_version_id: kbv.id,
                 organization_id: organization_id
               })

      assert is_nil(assistant.kaapi_uuid)
      assert config_version.status == :in_progress
    end

    test "returns error when knowledge_base_version_id is missing",
         %{organization_id: organization_id} do
      assert {:error, "Knowledge base is required for assistant creation"} =
               Assistants.create_assistant(%{
                 name: "No KB Assistant",
                 organization_id: organization_id
               })
    end

    test "uses default values when optional params are missing",
         %{organization_id: organization_id} do
      {:ok, kb} =
        Assistants.create_knowledge_base(%{
          name: "Default Test KB",
          organization_id: organization_id
        })

      {:ok, kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: kb.id,
          organization_id: organization_id,
          files: %{},
          status: :in_progress,
          llm_service_id: "vs_defaults_test",
          size: 0
        })

      assert {:ok, %{assistant: assistant, config_version: config_version}} =
               Assistants.create_assistant(%{
                 knowledge_base_version_id: kbv.id,
                 organization_id: organization_id
               })

      assert String.starts_with?(assistant.name, "Assistant-")
      assert config_version.model == "gpt-4o"
      assert config_version.prompt == "You are a helpful assistant"
      assert config_version.description == "Assistant configuration"

      temperature =
        config_version.settings[:temperature] || config_version.settings["temperature"]

      assert temperature == 1
    end
  end

  describe "create_assistant with in-progress KB" do
    setup [:enable_kaapi]

    test "skips Kaapi call and creates assistant with nil kaapi_uuid when KB is in-progress",
         %{organization_id: organization_id} do
      {:ok, kb} =
        Assistants.create_knowledge_base(%{
          name: "In-Progress KB",
          organization_id: organization_id
        })

      {:ok, kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: kb.id,
          organization_id: organization_id,
          files: %{"file_1" => %{"filename" => "doc.pdf"}},
          status: :in_progress,
          llm_service_id: "temporary-vs-abc123def456",
          size: 500
        })

      # No Tesla mock — if Kaapi is called, this will fail
      assert {:ok, %{assistant: assistant, config_version: config_version}} =
               Assistants.create_assistant(%{
                 name: "Deferred Assistant",
                 model: "gpt-4o",
                 instructions: "You are a helpful assistant",
                 temperature: 1.0,
                 knowledge_base_version_id: kbv.id,
                 organization_id: organization_id
               })

      assert is_nil(assistant.kaapi_uuid)
      assert config_version.status == :in_progress
    end
  end

  describe "create_assistant with already-completed KB" do
    setup [:enable_kaapi]

    test "registers with Kaapi immediately when KB callback arrived before assistant creation",
         %{organization_id: organization_id} do
      {:ok, kb} =
        Assistants.create_knowledge_base(%{
          name: "Already Completed KB",
          organization_id: organization_id
        })

      {:ok, kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: kb.id,
          organization_id: organization_id,
          files: %{"file_1" => %{"filename" => "doc.pdf"}},
          status: :completed,
          llm_service_id: "vs_already_ready_123",
          size: 500
        })

      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{data: %{id: "kaapi_uuid_from_create", version: %{version: 1}}}
          }
      end)

      assert {:ok, %{assistant: assistant}} =
               Assistants.create_assistant(%{
                 name: "Test Assistant",
                 model: "gpt-4o",
                 instructions: "You are a helpful assistant",
                 temperature: 1.0,
                 knowledge_base_version_id: kbv.id,
                 organization_id: organization_id
               })

      {:ok, updated_assistant} = Repo.fetch(Assistant, assistant.id, skip_organization_id: true)
      assert updated_assistant.kaapi_uuid == "kaapi_uuid_from_create"
    end

    test "marks config as failed when Kaapi config create fails for already-completed KB",
         %{organization_id: organization_id} do
      {:ok, kb} =
        Assistants.create_knowledge_base(%{
          name: "Completed KB Kaapi Fail",
          organization_id: organization_id
        })

      {:ok, kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: kb.id,
          organization_id: organization_id,
          files: %{"file_1" => %{"filename" => "doc.pdf"}},
          status: :completed,
          llm_service_id: "vs_kaapi_fail_456",
          size: 500
        })

      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 500, body: %{error: "Internal server error"}}
      end)

      assert {:error, reason} =
               Assistants.create_assistant(%{
                 name: "Fail Kaapi Assistant",
                 model: "gpt-4o",
                 instructions: "You are a helpful assistant",
                 temperature: 1.0,
                 knowledge_base_version_id: kbv.id,
                 organization_id: organization_id
               })

      assert reason =~ "Deferred Kaapi config creation failed"

      assistant =
        Repo.one(from a in Assistant, where: a.name == "Fail Kaapi Assistant", limit: 1)

      assert is_nil(assistant.kaapi_uuid)

      {:ok, updated_cv} =
        Repo.fetch(AssistantConfigVersion, assistant.active_config_version_id,
          skip_organization_id: true
        )

      assert updated_cv.status == :failed
      assert updated_cv.failure_reason =~ "Deferred Kaapi config creation failed"
    end
  end

  describe "handle_knowledge_base_callback deferred config" do
    setup [:enable_kaapi]

    test "creates deferred Kaapi config when KB callback is SUCCESSFUL",
         %{organization_id: organization_id} do
      {:ok, kb} =
        Assistants.create_knowledge_base(%{
          name: "Deferred KB",
          organization_id: organization_id
        })

      {:ok, kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: kb.id,
          organization_id: organization_id,
          files: %{"file_1" => %{"filename" => "doc.pdf"}},
          status: :in_progress,
          llm_service_id: "temporary-vs-abc123",
          size: 500,
          kaapi_job_id: "job_deferred_123"
        })

      # Create assistant with nil kaapi_uuid (simulating deferred creation)
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Deferred Assistant",
          organization_id: organization_id
        })
        |> Repo.insert()

      {:ok, config_version} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "You are a helpful assistant",
          settings: %{"temperature" => 1.0},
          status: :in_progress
        })
        |> Repo.insert()

      link_kbv_to_acv(kbv, config_version, organization_id)

      {:ok, assistant} =
        assistant
        |> Assistant.set_active_config_version_changeset(%{
          active_config_version_id: config_version.id
        })
        |> Repo.update()

      assert is_nil(assistant.kaapi_uuid)

      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{data: %{id: "kaapi_deferred_uuid_123", version: %{version: 1}}}
          }
      end)

      result =
        Assistants.handle_knowledge_base_callback(%{
          "data" => %{
            "job_id" => "job_deferred_123",
            "status" => "SUCCESSFUL",
            "collection" => %{"knowledge_base_id" => "real_vs_id_456"},
            "error_message" => nil
          }
        })

      assert %KnowledgeBaseVersion{} = result

      {:ok, updated_assistant} = Repo.fetch(Assistant, assistant.id, skip_organization_id: true)
      updated_assistant = updated_assistant |> Repo.preload([:active_config_version])
      assert updated_assistant.kaapi_uuid == "kaapi_deferred_uuid_123"
      assert updated_assistant.active_config_version.status == :ready

      {:ok, updated_cv} =
        Repo.fetch(AssistantConfigVersion, config_version.id, skip_organization_id: true)

      assert updated_cv.status == :ready
      assert updated_cv.kaapi_version_number == 1
    end

    test "marks config version as failed when deferred Kaapi call fails",
         %{organization_id: organization_id} do
      {:ok, kb} =
        Assistants.create_knowledge_base(%{
          name: "Failed Deferred KB",
          organization_id: organization_id
        })

      {:ok, kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: kb.id,
          organization_id: organization_id,
          files: %{"file_1" => %{"filename" => "doc.pdf"}},
          status: :in_progress,
          llm_service_id: "temporary-vs-fail123",
          size: 500,
          kaapi_job_id: "job_deferred_fail"
        })

      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Failed Deferred Assistant",
          organization_id: organization_id
        })
        |> Repo.insert()

      {:ok, config_version} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "You are a helpful assistant",
          settings: %{"temperature" => 1.0},
          status: :in_progress
        })
        |> Repo.insert()

      link_kbv_to_acv(kbv, config_version, organization_id)

      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 500, body: %{error: "Internal server error"}}
      end)

      _result =
        Assistants.handle_knowledge_base_callback(%{
          "data" => %{
            "job_id" => "job_deferred_fail",
            "status" => "SUCCESSFUL",
            "collection" => %{"knowledge_base_id" => "real_vs_id_789"},
            "error_message" => nil
          }
        })

      {:ok, updated_cv} =
        Repo.fetch(AssistantConfigVersion, config_version.id, skip_organization_id: true)

      assert updated_cv.status == :failed
      assert updated_cv.failure_reason =~ "Deferred Kaapi config creation failed"
    end

    test "preserves actual KB failure reason on deferred config when callback is FAILED",
         %{organization_id: organization_id} do
      {:ok, kb} =
        Assistants.create_knowledge_base(%{
          name: "KB With Real Error",
          organization_id: organization_id
        })

      {:ok, kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: kb.id,
          organization_id: organization_id,
          files: %{"file_1" => %{"filename" => "doc.pdf"}},
          status: :in_progress,
          llm_service_id: "temporary-vs-real-error",
          size: 500,
          kaapi_job_id: "job_real_error_123"
        })

      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Real Error Assistant",
          organization_id: organization_id
        })
        |> Repo.insert()

      {:ok, config_version} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "You are a helpful assistant",
          settings: %{"temperature" => 1.0},
          status: :in_progress
        })
        |> Repo.insert()

      link_kbv_to_acv(kbv, config_version, organization_id)

      {:ok, _assistant} =
        assistant
        |> Assistant.set_active_config_version_changeset(%{
          active_config_version_id: config_version.id
        })
        |> Repo.update()

      _result =
        Assistants.handle_knowledge_base_callback(%{
          "data" => %{
            "job_id" => "job_real_error_123",
            "status" => "FAILED",
            "error_message" => "Invalid documents: unsupported format"
          }
        })

      {:ok, updated_cv} =
        Repo.fetch(AssistantConfigVersion, config_version.id, skip_organization_id: true)

      assert updated_cv.status == :failed
      assert updated_cv.failure_reason == "Invalid documents: unsupported format"
    end
  end

  describe "update_assistant with in-progress KB (deferred update)" do
    setup [:enable_kaapi, :setup_assistant_with_kb]

    test "keeps old active_config_version_id when KB is in-progress",
         %{
           organization_id: organization_id,
           assistant: assistant,
           config_version: original_config_version
         } do
      {:ok, new_kb} =
        Assistants.create_knowledge_base(%{
          name: "New In-Progress KB",
          organization_id: organization_id
        })

      {:ok, new_kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: new_kb.id,
          organization_id: organization_id,
          files: %{"file_new" => %{"filename" => "new_doc.pdf"}},
          status: :in_progress,
          llm_service_id: "temporary-vs-update-test",
          size: 300
        })

      assert {:ok, result} =
               Assistants.update_assistant(assistant.id, %{
                 knowledge_base_version_id: new_kbv.id,
                 organization_id: organization_id
               })

      {:ok, updated_assistant} =
        Repo.fetch(Assistant, assistant.id, skip_organization_id: true)

      assert updated_assistant.active_config_version_id == original_config_version.id

      # A new config version should have been created but not activated
      config_count =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> Repo.aggregate(:count, :id)

      assert config_count == 2

      assert result.status == "ready"
    end

    test "callback after deferred update calls create_config_version and activates new config",
         %{
           organization_id: organization_id,
           assistant: assistant,
           config_version: original_config_version
         } do
      {:ok, new_kb} =
        Assistants.create_knowledge_base(%{
          name: "Deferred Update KB",
          organization_id: organization_id
        })

      {:ok, new_kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: new_kb.id,
          organization_id: organization_id,
          files: %{"file_new" => %{"filename" => "new_doc.pdf"}},
          status: :in_progress,
          llm_service_id: "temporary-vs-deferred-update",
          size: 300,
          kaapi_job_id: "job_deferred_update_123"
        })

      assert {:ok, _result} =
               Assistants.update_assistant(assistant.id, %{
                 knowledge_base_version_id: new_kbv.id,
                 name: "Updated Deferred Name",
                 organization_id: organization_id
               })

      # Verify active config is still the original
      {:ok, pre_callback_assistant} =
        Repo.fetch(Assistant, assistant.id, skip_organization_id: true)

      assert pre_callback_assistant.active_config_version_id == original_config_version.id

      # Now simulate SUCCESSFUL callback
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{data: %{id: "kaapi_config_version_update_123", version: 2}}
          }
      end)

      _result =
        Assistants.handle_knowledge_base_callback(%{
          "data" => %{
            "job_id" => "job_deferred_update_123",
            "status" => "SUCCESSFUL",
            "collection" => %{"knowledge_base_id" => "real_vs_id_update"},
            "error_message" => nil
          }
        })

      # After callback, active_config_version_id should be updated to new config
      {:ok, post_callback_assistant} =
        Repo.fetch(Assistant, assistant.id, skip_organization_id: true)

      assert post_callback_assistant.active_config_version_id != original_config_version.id

      # New config version should be :ready
      new_config =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> where([acv], acv.id != ^original_config_version.id)
        |> Repo.one()

      assert new_config.status == :ready
      assert new_config.kaapi_version_number == 2
    end

    test "callback failure after deferred update marks config as failed and keeps old active",
         %{
           organization_id: organization_id,
           assistant: assistant,
           config_version: original_config_version
         } do
      {:ok, new_kb} =
        Assistants.create_knowledge_base(%{
          name: "Failed Deferred Update KB",
          organization_id: organization_id
        })

      {:ok, new_kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: new_kb.id,
          organization_id: organization_id,
          files: %{"file_new" => %{"filename" => "new_doc.pdf"}},
          status: :in_progress,
          llm_service_id: "temporary-vs-failed-update",
          size: 300,
          kaapi_job_id: "job_deferred_update_fail"
        })

      # No Tesla mock for the update itself
      assert {:ok, _result} =
               Assistants.update_assistant(assistant.id, %{
                 knowledge_base_version_id: new_kbv.id,
                 organization_id: organization_id
               })

      _result =
        Assistants.handle_knowledge_base_callback(%{
          "data" => %{
            "job_id" => "job_deferred_update_fail",
            "status" => "FAILED",
            "collection" => nil,
            "error_message" => "Vector store creation failed due to invalid documents"
          }
        })

      # active_config_version_id should still be the original
      {:ok, post_callback_assistant} =
        Repo.fetch(Assistant, assistant.id, skip_organization_id: true)

      assert post_callback_assistant.active_config_version_id == original_config_version.id

      # New config version should be :failed
      new_config =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> where([acv], acv.id != ^original_config_version.id)
        |> Repo.one()

      assert new_config.status == :failed
      assert new_config.failure_reason =~ "Vector store creation failed due to invalid documents"
    end

    test "returns error when deferred_update_transaction fails due to duplicate assistant name",
         %{
           organization_id: organization_id,
           assistant: existing_assistant
         } do
      {:ok, second_assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Second Assistant",
          organization_id: organization_id,
          kaapi_uuid: "second_kaapi_uuid_unique_test"
        })
        |> Repo.insert()

      # Create an in-progress KB to trigger the deferred update path
      {:ok, new_kb} =
        Assistants.create_knowledge_base(%{
          name: "In-Progress KB for Name Conflict",
          organization_id: organization_id
        })

      {:ok, new_kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: new_kb.id,
          organization_id: organization_id,
          files: %{"file_new" => %{"filename" => "new_doc.pdf"}},
          status: :in_progress,
          llm_service_id: "temporary-vs-name-conflict-test",
          size: 300
        })

      # Attempt to rename existing_assistant to the name already taken by second_assistant.
      # deferred_update_transaction should fail on the unique [:name, :organization_id] constraint.
      assert {:error, changeset} =
               Assistants.update_assistant(existing_assistant.id, %{
                 knowledge_base_version_id: new_kbv.id,
                 name: second_assistant.name,
                 organization_id: organization_id
               })

      assert %{name: ["has already been taken"]} == errors_on(changeset)
    end
  end

  describe "delete_assistant/1" do
    test "deletes assistant with kaapi_uuid ",
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

    test "deletes assistant when kaapi_uuid is nil without calling Kaapi",
         %{organization_id: organization_id} do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "No Kaapi UUID Assistant",
          organization_id: organization_id
        })
        |> Repo.insert()

      # No Tesla mock — if Kaapi is called, this will fail
      assert {:ok, %Assistant{}} = Assistants.delete_assistant(assistant.id)
      assert {:error, _} = Repo.fetch(Assistant, assistant.id, skip_organization_id: true)
    end
  end

  describe "Assistant changeset unique constraints" do
    test "rejects duplicate name within the same organization",
         %{organization_id: organization_id} do
      assert {:ok, _} =
               %Assistant{}
               |> Assistant.changeset(%{
                 name: "Unique Name Test",
                 organization_id: organization_id
               })
               |> Repo.insert()

      assert {:error, changeset} =
               %Assistant{}
               |> Assistant.changeset(%{
                 name: "Unique Name Test",
                 organization_id: organization_id
               })
               |> Repo.insert()

      assert {"has already been taken", _} = changeset.errors[:name]
    end

    test "rejects duplicate assistant_display_id",
         %{organization_id: organization_id} do
      assert {:ok, first} =
               %Assistant{}
               |> Assistant.changeset(%{
                 name: "Display ID Test A",
                 organization_id: organization_id
               })
               |> Repo.insert()

      assert {:error, changeset} =
               %Assistant{}
               |> Assistant.changeset(%{
                 name: "Display ID Test B",
                 organization_id: organization_id,
                 assistant_display_id: first.assistant_display_id
               })
               |> Repo.insert()

      assert {"has already been taken", _} = changeset.errors[:assistant_display_id]
    end
  end

  describe "end-to-end: create assistant, receive callback, verify state" do
    setup [:enable_kaapi]

    test "create assistant -> KB callback -> Kaapi config created -> correct DB state",
         %{organization_id: organization_id} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{job_id: "job_001"}}}
      end)

      {:ok, %{knowledge_base_version: kbv}} =
        Assistants.create_knowledge_base_with_version(%{
          media_info: [
            %{file_id: "file_1", filename: "doc.pdf", uploaded_at: DateTime.utc_now()}
          ],
          organization_id: organization_id
        })

      assert kbv.status == :in_progress

      # Create assistant while KB is still processing
      assert {:ok, %{assistant: assistant, config_version: config_version}} =
               Assistants.create_assistant(%{
                 name: "Test Assistant",
                 model: "gpt-4o",
                 instructions: "You are a helpful assistant",
                 temperature: 0.7,
                 knowledge_base_version_id: kbv.id,
                 organization_id: organization_id
               })

      # Verify initial state: no kaapi_uuid, config in progress
      assert is_nil(assistant.kaapi_uuid)
      assert config_version.status == :in_progress
      assert assistant.active_config_version_id == config_version.id

      # Verify get_assistant returns new_version_in_progress: true
      {:ok, fetched} = Assistants.get_assistant(assistant.id)
      assert fetched.new_version_in_progress == true
      assert fetched.status == "in_progress"
      assert is_nil(fetched.assistant_id)

      # SUCCESSFUL KB callback from Kaapi
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{id: "kaapi_uuid_001", version: %{version: 1}}}}
      end)

      result =
        Assistants.handle_knowledge_base_callback(%{
          "data" => %{
            "job_id" => "job_001",
            "status" => "SUCCESSFUL",
            "collection" => %{"knowledge_base_id" => "vs_001"},
            "error_message" => nil
          }
        })

      assert %KnowledgeBaseVersion{} = result

      # Step 4: Verify final DB state
      {:ok, updated_assistant} = Repo.fetch(Assistant, assistant.id, skip_organization_id: true)
      assert updated_assistant.kaapi_uuid == "kaapi_uuid_001"

      {:ok, updated_cv} =
        Repo.fetch(AssistantConfigVersion, config_version.id, skip_organization_id: true)

      assert updated_cv.status == :ready

      {:ok, updated_kbv} = Repo.fetch(KnowledgeBaseVersion, kbv.id, skip_organization_id: true)
      assert updated_kbv.status == :completed
      assert updated_kbv.llm_service_id == "vs_001"

      # Verify get_assistant now shows ready state
      {:ok, final_fetched} = Assistants.get_assistant(assistant.id)
      assert final_fetched.new_version_in_progress == false
      assert final_fetched.status == "ready"
      assert final_fetched.assistant_id == "kaapi_uuid_001"
    end

    test "create assistant -> successful KB callback -> update KB -> FAILED KB callback",
         %{organization_id: organization_id} do
      failure_reason = "Document parsing failed: corrupt file"
      # Step 1: Create KB + assistant
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{job_id: "job_lifecycle_001"}}}
      end)

      {:ok, %{knowledge_base_version: kbv}} =
        Assistants.create_knowledge_base_with_version(%{
          media_info: [
            %{file_id: "file_1", filename: "doc.pdf", uploaded_at: DateTime.utc_now()}
          ],
          organization_id: organization_id
        })

      assert {:ok, %{assistant: assistant, config_version: config_version}} =
               Assistants.create_assistant(%{
                 name: "Test Assistant",
                 model: "gpt-4o",
                 instructions: "You are a helpful assistant",
                 temperature: 0.7,
                 knowledge_base_version_id: kbv.id,
                 organization_id: organization_id
               })

      # Step 2: SUCCESSFUL KB callback -> Kaapi config created
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{data: %{id: "kaapi_uuid_lifecycle", version: %{version: 1}}}
          }
      end)

      _result =
        Assistants.handle_knowledge_base_callback(%{
          "data" => %{
            "job_id" => "job_lifecycle_001",
            "status" => "SUCCESSFUL",
            "collection" => %{"knowledge_base_id" => "vs_lifecycle_001"},
            "error_message" => nil
          }
        })

      # Verify first version is ready
      {:ok, ready_assistant} = Repo.fetch(Assistant, assistant.id, skip_organization_id: true)
      assert ready_assistant.kaapi_uuid == "kaapi_uuid_lifecycle"

      {:ok, ready_cv} =
        Repo.fetch(AssistantConfigVersion, config_version.id, skip_organization_id: true)

      assert ready_cv.status == :ready

      # Step 3: Update assistant with a new KB
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{job_id: "job_lifecycle_002"}}}
      end)

      {:ok, %{knowledge_base_version: new_kbv}} =
        Assistants.create_knowledge_base_with_version(%{
          media_info: [
            %{file_id: "file_2", filename: "new_doc.pdf", uploaded_at: DateTime.utc_now()}
          ],
          organization_id: organization_id
        })

      assert {:ok, _result} =
               Assistants.update_assistant(assistant.id, %{
                 knowledge_base_version_id: new_kbv.id,
                 name: "Updated Assistant",
                 organization_id: organization_id
               })

      # Step 4: New KB callback FAILS
      _result =
        Assistants.handle_knowledge_base_callback(%{
          "data" => %{
            "job_id" => "job_lifecycle_002",
            "status" => "FAILED",
            "collection" => nil,
            "error_message" => failure_reason
          }
        })

      # New config version should be failed with real error
      new_cv =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> where([acv], acv.id != ^config_version.id)
        |> Repo.one()

      assert new_cv.status == :failed
      assert new_cv.failure_reason == failure_reason

      # Active config should still be the original ready version
      {:ok, post_fail} = Repo.fetch(Assistant, assistant.id, skip_organization_id: true)
      assert post_fail.active_config_version_id == config_version.id
      assert post_fail.kaapi_uuid == "kaapi_uuid_lifecycle"

      # Original config version should still be ready
      {:ok, original_cv} =
        Repo.fetch(AssistantConfigVersion, config_version.id, skip_organization_id: true)

      assert original_cv.status == :ready

      # A failure notification should have been created with the correct message
      notification =
        Notification
        |> where([n], n.organization_id == ^organization_id)
        |> order_by([n], desc: n.inserted_at)
        |> limit(1)
        |> Repo.one()

      {:ok, fetched} = Assistants.get_assistant(assistant.id)

      assert notification.entity["config_version_id"] == new_cv.id

      assert notification.message ==
               "Knowledge Base creation failed for assistant \"#{fetched.name}\". Reason: #{failure_reason}. Please try again."

      # get_assistant should show the assistant is still functional with original version
      assert fetched.status == "ready"
      assert fetched.name == "Updated Assistant"
    end
  end

  describe "end-to-end: create assistant — failure cases" do
    setup [:enable_kaapi]

    test "create assistant -> FAILED KB callback -> config version marked as failed with real error",
         %{organization_id: organization_id} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{job_id: "job_fail_001"}}}
      end)

      {:ok, %{knowledge_base_version: kbv}} =
        Assistants.create_knowledge_base_with_version(%{
          media_info: [
            %{file_id: "file_1", filename: "doc.pdf", uploaded_at: DateTime.utc_now()}
          ],
          organization_id: organization_id
        })

      assert {:ok, %{assistant: assistant, config_version: config_version}} =
               Assistants.create_assistant(%{
                 name: "Test Assistant",
                 model: "gpt-4o",
                 instructions: "You are a helpful assistant",
                 temperature: 0.7,
                 knowledge_base_version_id: kbv.id,
                 organization_id: organization_id
               })

      assert is_nil(assistant.kaapi_uuid)
      assert config_version.status == :in_progress

      # FAILED KB callback
      _result =
        Assistants.handle_knowledge_base_callback(%{
          "data" => %{
            "job_id" => "job_fail_001",
            "status" => "FAILED",
            "collection" => nil,
            "error_message" => "Invalid documents: unsupported format"
          }
        })

      # Config version should be failed with the actual error message
      {:ok, updated_cv} =
        Repo.fetch(AssistantConfigVersion, config_version.id, skip_organization_id: true)

      assert updated_cv.status == :failed
      assert updated_cv.failure_reason == "Invalid documents: unsupported format"

      # Assistant should still have no kaapi_uuid
      {:ok, updated_assistant} = Repo.fetch(Assistant, assistant.id, skip_organization_id: true)
      assert is_nil(updated_assistant.kaapi_uuid)

      # KB version should be failed
      {:ok, updated_kbv} = Repo.fetch(KnowledgeBaseVersion, kbv.id, skip_organization_id: true)
      assert updated_kbv.status == :failed
    end

    test "create assistant -> SUCCESSFUL KB callback -> Kaapi config creation fails -> config version marked as failed",
         %{organization_id: organization_id} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{job_id: "job_fail_002"}}}
      end)

      {:ok, %{knowledge_base_version: kbv}} =
        Assistants.create_knowledge_base_with_version(%{
          media_info: [
            %{file_id: "file_1", filename: "doc.pdf", uploaded_at: DateTime.utc_now()}
          ],
          organization_id: organization_id
        })

      assert {:ok, %{assistant: assistant, config_version: config_version}} =
               Assistants.create_assistant(%{
                 name: "Test Assistant",
                 model: "gpt-4o",
                 instructions: "You are a helpful assistant",
                 temperature: 0.7,
                 knowledge_base_version_id: kbv.id,
                 organization_id: organization_id
               })

      # KB callback succeeds, but Kaapi config creation fails
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 500, body: %{"error" => "Internal server error"}}
      end)

      _result =
        Assistants.handle_knowledge_base_callback(%{
          "data" => %{
            "job_id" => "job_fail_002",
            "status" => "SUCCESSFUL",
            "collection" => %{"knowledge_base_id" => "vs_fail_002"},
            "error_message" => nil
          }
        })

      # Config version should be failed with Kaapi error
      {:ok, updated_cv} =
        Repo.fetch(AssistantConfigVersion, config_version.id, skip_organization_id: true)

      assert updated_cv.status == :failed
      assert updated_cv.failure_reason =~ "Deferred Kaapi config creation failed"

      # Assistant should still have no kaapi_uuid
      {:ok, updated_assistant} = Repo.fetch(Assistant, assistant.id, skip_organization_id: true)
      assert is_nil(updated_assistant.kaapi_uuid)

      # KB version should still be completed (KB itself succeeded)
      {:ok, updated_kbv} = Repo.fetch(KnowledgeBaseVersion, kbv.id, skip_organization_id: true)
      assert updated_kbv.status == :completed
    end
  end

  describe "end-to-end: callback arrives before assistant save" do
    setup [:enable_kaapi]

    test "KB callback completes first, then assistant creation registers with Kaapi immediately",
         %{organization_id: organization_id} do
      # Create KB and simulate immediate callback (before assistant is saved)
      {:ok, kb} =
        Assistants.create_knowledge_base(%{
          name: "Test KB",
          organization_id: organization_id
        })

      {:ok, kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: kb.id,
          organization_id: organization_id,
          files: %{"file_1" => %{"filename" => "doc.pdf"}},
          status: :in_progress,
          llm_service_id: "temporary-vs-001",
          size: 500,
          kaapi_job_id: "job_002"
        })

      # Callback arrives — no assistant exists yet, so no config version to update
      _result =
        Assistants.handle_knowledge_base_callback(%{
          "data" => %{
            "job_id" => "job_002",
            "status" => "SUCCESSFUL",
            "collection" => %{"knowledge_base_id" => "vs_002"},
            "error_message" => nil
          }
        })

      {:ok, completed_kbv} = Repo.fetch(KnowledgeBaseVersion, kbv.id, skip_organization_id: true)
      completed_kbv = completed_kbv |> Repo.preload(:assistant_config_versions)

      assert completed_kbv.assistant_config_versions == []
      assert completed_kbv.status == :completed

      # User now saves assistant — KB is already completed, should register with Kaapi immediately
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{id: "kaapi_uuid_002", version: %{version: 1}}}}
      end)

      assert {:ok, %{assistant: assistant, config_version: config_version}} =
               Assistants.create_assistant(%{
                 name: "Test Assistant",
                 model: "gpt-4o",
                 instructions: "You are a helpful assistant",
                 temperature: 1.0,
                 knowledge_base_version_id: kbv.id,
                 organization_id: organization_id
               })

      # Verify assistant was registered with Kaapi immediately
      {:ok, updated_assistant} = Repo.fetch(Assistant, assistant.id, skip_organization_id: true)
      assert updated_assistant.kaapi_uuid == "kaapi_uuid_002"

      {:ok, updated_cv} =
        Repo.fetch(AssistantConfigVersion, config_version.id, skip_organization_id: true)

      assert updated_cv.status == :ready

      # Verify get_assistant shows correct state
      {:ok, fetched} = Assistants.get_assistant(assistant.id)
      assert fetched.new_version_in_progress == false
      assert fetched.status == "ready"
      assert fetched.assistant_id == "kaapi_uuid_002"
    end
  end

  describe "end-to-end: callback arrives before save — failure cases" do
    setup [:enable_kaapi]

    test "FAILED KB callback first, then assistant creation -> config stays in_progress with failed KB",
         %{organization_id: organization_id} do
      {:ok, kb} =
        Assistants.create_knowledge_base(%{
          name: "Test KB",
          organization_id: organization_id
        })

      {:ok, kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: kb.id,
          organization_id: organization_id,
          files: %{"file_1" => %{"filename" => "doc.pdf"}},
          status: :in_progress,
          llm_service_id: "temporary-vs-001",
          size: 500,
          kaapi_job_id: "job_late_fail_001"
        })

      # FAILED callback arrives before assistant is saved
      _result =
        Assistants.handle_knowledge_base_callback(%{
          "data" => %{
            "job_id" => "job_late_fail_001",
            "status" => "FAILED",
            "collection" => nil,
            "error_message" => "Document parsing failed"
          }
        })

      {:ok, failed_kbv} = Repo.fetch(KnowledgeBaseVersion, kbv.id, skip_organization_id: true)
      assert failed_kbv.status == :failed

      # User saves assistant with the failed KB
      assert {:ok, %{assistant: assistant, config_version: config_version}} =
               Assistants.create_assistant(%{
                 name: "Test Assistant",
                 model: "gpt-4o",
                 instructions: "You are a helpful assistant",
                 temperature: 1.0,
                 knowledge_base_version_id: kbv.id,
                 organization_id: organization_id
               })

      # No Kaapi registration since KB failed — kaapi_uuid stays nil
      assert is_nil(assistant.kaapi_uuid)
      assert config_version.status == :failed
    end

    test "SUCCESSFUL KB callback first, then assistant creation fails to register with Kaapi",
         %{organization_id: organization_id} do
      {:ok, kb} =
        Assistants.create_knowledge_base(%{
          name: "Test KB",
          organization_id: organization_id
        })

      {:ok, kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: kb.id,
          organization_id: organization_id,
          files: %{"file_1" => %{"filename" => "doc.pdf"}},
          status: :in_progress,
          llm_service_id: "temporary-vs-001",
          size: 500,
          kaapi_job_id: "job_late_fail_002"
        })

      # SUCCESSFUL callback arrives before assistant is saved
      _result =
        Assistants.handle_knowledge_base_callback(%{
          "data" => %{
            "job_id" => "job_late_fail_002",
            "status" => "SUCCESSFUL",
            "collection" => %{"knowledge_base_id" => "vs_late_002"},
            "error_message" => nil
          }
        })

      # Kaapi config creation will fail when assistant is saved
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 500, body: %{"error" => "Service unavailable"}}
      end)

      assert {:error, _reason} =
               Assistants.create_assistant(%{
                 name: "Test Assistant",
                 model: "gpt-4o",
                 instructions: "You are a helpful assistant",
                 temperature: 1.0,
                 knowledge_base_version_id: kbv.id,
                 organization_id: organization_id
               })
    end
  end

  describe "end-to-end: update assistant" do
    setup [:enable_kaapi, :setup_assistant_with_kb]

    test "update assistant with same KB -> new config version registered with Kaapi",
         %{
           organization_id: organization_id,
           assistant: assistant,
           config_version: original_cv
         } do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{id: "kaapi_cv_001", version: 2}}}
      end)

      assert {:ok, result} =
               Assistants.update_assistant(assistant.id, %{
                 name: "Updated Assistant",
                 instructions: "You are a specialized assistant",
                 temperature: 0.5,
                 organization_id: organization_id
               })

      assert result.name == "Updated Assistant"
      assert result.instructions == "You are a specialized assistant"
      assert result.temperature == 0.5

      # Verify new config version was created
      config_count =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> Repo.aggregate(:count, :id)

      assert config_count == 2

      # New config version should be ready
      new_cv =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> where([acv], acv.id != ^original_cv.id)
        |> Repo.one()

      assert new_cv.status == :ready
      assert new_cv.prompt == "You are a specialized assistant"

      # get_assistant should show updated state
      {:ok, fetched} = Assistants.get_assistant(assistant.id)
      assert fetched.new_version_in_progress == false
      assert fetched.status == "ready"
      assert fetched.name == "Updated Assistant"
    end

    test "update assistant with new  KB -> FAILED callback -> config version marked as failed",
         %{
           organization_id: organization_id,
           assistant: assistant,
           config_version: original_cv
         } do
      # Create a new KB that's still processing
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{job_id: "job_upd_fail_001"}}}
      end)

      {:ok, %{knowledge_base_version: new_kbv}} =
        Assistants.create_knowledge_base_with_version(%{
          media_info: [
            %{file_id: "new_file", filename: "new.pdf", uploaded_at: DateTime.utc_now()}
          ],
          organization_id: organization_id
        })

      # Update assistant with the new in-progress KB
      assert {:ok, _result} =
               Assistants.update_assistant(assistant.id, %{
                 knowledge_base_version_id: new_kbv.id,
                 name: "Updated Assistant",
                 organization_id: organization_id
               })

      # FAILED KB callback
      _result =
        Assistants.handle_knowledge_base_callback(%{
          "data" => %{
            "job_id" => "job_upd_fail_001",
            "status" => "FAILED",
            "collection" => nil,
            "error_message" => "Document processing failed: corrupt file"
          }
        })

      # New config version should be failed with real error
      new_cv =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> where([acv], acv.id != ^original_cv.id)
        |> Repo.one()

      assert new_cv.status == :failed
      assert new_cv.failure_reason == "Document processing failed: corrupt file"

      # Active config should still be the original
      {:ok, post_callback} = Repo.fetch(Assistant, assistant.id, skip_organization_id: true)
      assert post_callback.active_config_version_id == original_cv.id
    end

    test "update assistant with new in-progress KB -> SUCCESSFUL callback -> Kaapi config fails",
         %{
           organization_id: organization_id,
           assistant: assistant,
           config_version: original_cv
         } do
      # Create a new KB that's still processing
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{job_id: "job_upd_fail_002"}}}
      end)

      {:ok, %{knowledge_base_version: new_kbv}} =
        Assistants.create_knowledge_base_with_version(%{
          media_info: [
            %{file_id: "new_file", filename: "new.pdf", uploaded_at: DateTime.utc_now()}
          ],
          organization_id: organization_id
        })

      # Update assistant with the new in-progress KB
      assert {:ok, _result} =
               Assistants.update_assistant(assistant.id, %{
                 knowledge_base_version_id: new_kbv.id,
                 name: "Updated Assistant",
                 organization_id: organization_id
               })

      # SUCCESSFUL KB callback, but Kaapi config creation fails
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 500, body: %{"error" => "Kaapi unavailable"}}
      end)

      _result =
        Assistants.handle_knowledge_base_callback(%{
          "data" => %{
            "job_id" => "job_upd_fail_002",
            "status" => "SUCCESSFUL",
            "collection" => %{"knowledge_base_id" => "vs_upd_fail_002"},
            "error_message" => nil
          }
        })

      # New config version should be failed with Kaapi error
      new_cv =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> where([acv], acv.id != ^original_cv.id)
        |> Repo.one()

      assert new_cv.status == :failed
      assert new_cv.failure_reason =~ "Deferred Kaapi config"

      # Active config should still be the original
      {:ok, post_callback} = Repo.fetch(Assistant, assistant.id, skip_organization_id: true)
      assert post_callback.active_config_version_id == original_cv.id

      # KB version should still be completed
      {:ok, updated_kbv} =
        Repo.fetch(KnowledgeBaseVersion, new_kbv.id, skip_organization_id: true)

      assert updated_kbv.status == :completed
    end

    test "update assistant with new in-progress KB -> deferred, then callback completes",
         %{
           organization_id: organization_id,
           assistant: assistant,
           config_version: original_cv
         } do
      # Create a new KB that's still processing
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{job_id: "job_003"}}}
      end)

      {:ok, %{knowledge_base_version: new_kbv}} =
        Assistants.create_knowledge_base_with_version(%{
          media_info: [
            %{file_id: "new_file", filename: "new.pdf", uploaded_at: DateTime.utc_now()}
          ],
          organization_id: organization_id
        })

      # Update assistant with the new in-progress KB
      assert {:ok, _result} =
               Assistants.update_assistant(assistant.id, %{
                 knowledge_base_version_id: new_kbv.id,
                 name: "Updated Assistant",
                 organization_id: organization_id
               })

      # Active config should still be the original (deferred)
      {:ok, pre_callback} = Repo.fetch(Assistant, assistant.id, skip_organization_id: true)
      assert pre_callback.active_config_version_id == original_cv.id

      # A new config version should exist but not be active
      config_count =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> Repo.aggregate(:count, :id)

      assert config_count == 2

      # get_assistant should show new_version_in_progress
      {:ok, fetched} = Assistants.get_assistant(assistant.id)
      assert fetched.new_version_in_progress == true

      # Simulate SUCCESSFUL KB callback
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{data: %{id: "kaapi_cv_002", version: 3}}}
      end)

      _result =
        Assistants.handle_knowledge_base_callback(%{
          "data" => %{
            "job_id" => "job_003",
            "status" => "SUCCESSFUL",
            "collection" => %{"knowledge_base_id" => "vs_003"},
            "error_message" => nil
          }
        })

      # After callback, active config should be the new one
      {:ok, post_callback} = Repo.fetch(Assistant, assistant.id, skip_organization_id: true)
      assert post_callback.active_config_version_id != original_cv.id

      new_cv =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> where([acv], acv.id != ^original_cv.id)
        |> Repo.one()

      assert new_cv.status == :ready

      # get_assistant should show final ready state
      {:ok, final_fetched} = Assistants.get_assistant(assistant.id)
      assert final_fetched.new_version_in_progress == false
      assert final_fetched.status == "ready"
    end

    test "returns error when a config version is still in progress",
         %{
           organization_id: organization_id,
           assistant: assistant
         } do
      # Insert an in-progress config version for this assistant
      {:ok, _in_progress_cv} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "pending prompt",
          settings: %{"temperature" => 1.0},
          status: :in_progress
        })
        |> Repo.insert()

      assert {:error, "Assistant setup is still in progress"} =
               Assistants.update_assistant(assistant.id, %{
                 name: "Should Fail",
                 organization_id: organization_id
               })
    end
  end
end
