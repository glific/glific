defmodule GlificWeb.Resolvers.AssistantsTest do
  @moduledoc """
  Test suite for GraphQL resolvers related to Assistants.
  """
  use GlificWeb.ConnCase
  use Oban.Pro.Testing, repo: Glific.Repo
  use Wormwood.GQLCase

  import Ecto.Query

  alias Glific.Assistants
  alias Glific.Assistants.Assistant
  alias Glific.Assistants.AssistantConfigVersion
  alias Glific.Partners
  alias Glific.Repo
  alias Glific.ThirdParty.Kaapi.AssistantCloneWorker

  load_gql(
    :create_knowledge_base,
    GlificWeb.Schema,
    "assets/gql/assistants/create_knowledge_base.gql"
  )

  load_gql(
    :list_assistant_config_versions,
    GlificWeb.Schema,
    "assets/gql/assistants/list_assistant_config_versions.gql"
  )

  load_gql(
    :assistant_versions,
    GlificWeb.Schema,
    "assets/gql/assistants/assistant_versions.gql"
  )

  load_gql(
    :set_live_version,
    GlificWeb.Schema,
    "assets/gql/assistants/set_live_version.gql"
  )

  load_gql(
    :get_file,
    GlificWeb.Schema,
    "assets/gql/assistants/file_result.gql"
  )

  describe "create_knowledge_base/3" do
    setup :enable_kaapi

    test "creates and returns knowledge base on success", %{manager: user} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{
              data: %{job_id: "job_abc123"}
            }
          }
      end)

      {:ok, query_data} =
        auth_query_gql_by(:create_knowledge_base, user,
          variables: %{
            "media_info" => [
              %{"file_id" => "file_abc", "filename" => "doc.pdf"},
              %{"file_id" => "file_xyz", "filename" => "notes.txt"}
            ]
          }
        )

      knowledge_base = query_data.data["create_knowledge_base"]["knowledge_base"]
      assert knowledge_base["id"] != nil
      assert knowledge_base["name"] != nil
      assert knowledge_base["knowledge_base_version_id"] != nil
      assert knowledge_base["status"] == "in_progress"
    end

    test "returns knowledge base without creating one", %{
      manager: user,
      organization_id: organization_id
    } do
      {:ok, knowledge_base} =
        Assistants.create_knowledge_base(%{
          name: "Test Knowledge Base",
          organization_id: organization_id
        })

      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{
              data: %{job_id: "job_abc123"}
            }
          }
      end)

      {:ok, query_data} =
        auth_query_gql_by(:create_knowledge_base, user,
          variables: %{
            "id" => knowledge_base.id,
            "media_info" => [
              %{"file_id" => "file_abc", "filename" => "doc.pdf"},
              %{"file_id" => "file_xyz", "filename" => "notes.txt"}
            ]
          }
        )

      response = query_data.data["create_knowledge_base"]["knowledge_base"]

      assert response["id"] == to_string(knowledge_base.id)
      assert response["name"] == knowledge_base.name
      assert response["knowledge_base_version_id"] != nil
      assert response["status"] == "in_progress"
    end

    test "returns error when kaapi api fails", %{manager: user} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 500,
            body: %{error: "Internal server error"}
          }
      end)

      {:ok, query_data} =
        auth_query_gql_by(:create_knowledge_base, user,
          variables: %{
            "media_info" => [
              %{"file_id" => "file_abc", "filename" => "doc.pdf"}
            ]
          }
        )

      assert query_data.data["create_knowledge_base"] == nil
      assert [error | _] = query_data.errors
      assert error[:message] == "Failed to create knowledge base"
    end

    test "returns nil knowledge base when media_info is empty", %{manager: user} do
      {:ok, query_data} =
        auth_query_gql_by(:create_knowledge_base, user, variables: %{"media_info" => []})

      assert query_data.data["create_knowledge_base"]["knowledge_base"] == nil
      assert query_data.data["create_knowledge_base"]["errors"] == nil
      assert Map.get(query_data, :errors) == nil
    end

    test "returns nil knowledge base when media_info is empty, regardless of id", %{manager: user} do
      {:ok, query_data} =
        auth_query_gql_by(:create_knowledge_base, user,
          variables: %{"id" => 0, "media_info" => []}
        )

      assert query_data.data["create_knowledge_base"]["knowledge_base"] == nil
      assert query_data.data["create_knowledge_base"]["errors"] == nil
      assert Map.get(query_data, :errors) == nil
    end
  end

  describe "list_assistant_config_versions/3" do
    setup :enable_kaapi

    test "returns all config versions for the organization", %{
      manager: user,
      organization_id: organization_id
    } do
      {:ok, {assistant, _config_version}} = create_assistant_with_config_version(organization_id)

      assistant_configuration_version_list =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> Repo.all()

      assert length(assistant_configuration_version_list) == 3

      {:ok, query_data} = auth_query_gql_by(:list_assistant_config_versions, user)

      versions = query_data.data["assistantConfigVersions"]
      assert length(versions) == 1
      assert hd(versions)["status"] == "ready"
    end
  end

  defp create_assistant_with_config_version(organization_id, kaapi_uuid \\ nil) do
    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{
        name: "Test Assistant #{System.unique_integer()}",
        organization_id: organization_id,
        kaapi_uuid: kaapi_uuid
      })
      |> Repo.insert()

    {:ok, _config_version1} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        prompt: "You are a helpful assistant",
        model: "gpt-4o",
        provider: "openai",
        settings: %{},
        status: :failed,
        organization_id: organization_id
      })
      |> Repo.insert()

    {:ok, _config_version2} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        prompt: "You are a helpful assistant",
        model: "gpt-4o",
        provider: "openai",
        settings: %{},
        status: :in_progress,
        organization_id: organization_id
      })
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        prompt: "You are a helpful assistant",
        model: "gpt-4o",
        provider: "openai",
        settings: %{},
        status: :ready,
        organization_id: organization_id
      })
      |> Repo.insert()

    {:ok, kb} =
      Assistants.create_knowledge_base(%{name: "Legacy KB", organization_id: organization_id})

    {:ok, kb_version} =
      Assistants.create_knowledge_base_version(%{
        knowledge_base_id: kb.id,
        organization_id: organization_id,
        status: :completed,
        llm_service_id: "vs_legacy_123",
        size: 100,
        files: %{}
      })

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all("assistant_config_version_knowledge_base_versions", [
      %{
        assistant_config_version_id: config_version.id,
        knowledge_base_version_id: kb_version.id,
        organization_id: organization_id,
        inserted_at: now,
        updated_at: now
      }
    ])

    {:ok, assistant} =
      assistant
      |> Assistant.set_active_config_version_changeset(%{
        active_config_version_id: config_version.id
      })
      |> Repo.update()

    {:ok, {assistant, config_version}}
  end

  load_gql(
    :clone_assistant,
    GlificWeb.Schema,
    "assets/gql/assistants/clone_assistant.gql"
  )

  describe "clone_assistant/3" do
    setup :enable_kaapi

    test "initiates clone for a legacy assistant", %{
      manager: user,
      organization_id: organization_id
    } do
      {:ok, {assistant, _config_version}} =
        create_assistant_with_config_version(organization_id, "kaapi_clone_test")

      {:ok, query_data} =
        auth_query_gql_by(:clone_assistant, user, variables: %{"id" => assistant.id})

      result = query_data.data["cloneAssistant"]
      assert result["message"] == "Assistant clone initiated"
      assert result["errors"] == nil
    end

    test "initiates clone for a non-legacy assistant with version_id", %{
      manager: user,
      organization_id: organization_id
    } do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Non-Legacy Assistant",
          organization_id: organization_id,
          kaapi_uuid: "kaapi_non_legacy_test"
        })
        |> Repo.insert()

      {:ok, nl_kb} =
        Assistants.create_knowledge_base(%{
          name: "Non-Legacy KB",
          organization_id: organization_id
        })

      {:ok, nl_kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: nl_kb.id,
          organization_id: organization_id,
          files: %{"file_1" => %{"name" => "doc.pdf"}},
          status: :completed,
          llm_service_id: "kaapi_kb_id_789",
          kaapi_job_id: "kaapi_job_123",
          size: 500
        })

      {:ok, nl_config_version} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "You are a non-legacy assistant",
          settings: %{},
          status: :ready
        })
        |> Repo.insert()

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert_all("assistant_config_version_knowledge_base_versions", [
        %{
          assistant_config_version_id: nl_config_version.id,
          knowledge_base_version_id: nl_kbv.id,
          organization_id: organization_id,
          inserted_at: now,
          updated_at: now
        }
      ])

      {:ok, _assistant} =
        assistant
        |> Assistant.set_active_config_version_changeset(%{
          active_config_version_id: nl_config_version.id
        })
        |> Repo.update()

      {:ok, query_data} =
        auth_query_gql_by(:clone_assistant, user,
          variables: %{"id" => assistant.id, "version_id" => nl_config_version.id}
        )

      result = query_data.data["cloneAssistant"]
      assert result["message"] == "Assistant clone initiated"
      assert result["errors"] == nil
    end

    test "returns error when a clone is already in progress", %{
      manager: user,
      organization_id: organization_id
    } do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Conflict Test Assistant",
          organization_id: organization_id,
          kaapi_uuid: "kaapi_conflict_test"
        })
        |> Repo.insert()

      {:ok, nl_kb} =
        Assistants.create_knowledge_base(%{
          name: "Conflict Test KB",
          organization_id: organization_id
        })

      {:ok, nl_kbv} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: nl_kb.id,
          organization_id: organization_id,
          files: %{},
          status: :completed,
          llm_service_id: "kaapi_kb_conflict",
          kaapi_job_id: "kaapi_job_conflict",
          size: 100
        })

      {:ok, nl_config_version} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "Conflict test prompt",
          settings: %{},
          status: :ready
        })
        |> Repo.insert()

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert_all("assistant_config_version_knowledge_base_versions", [
        %{
          assistant_config_version_id: nl_config_version.id,
          knowledge_base_version_id: nl_kbv.id,
          organization_id: organization_id,
          inserted_at: now,
          updated_at: now
        }
      ])

      {:ok, _assistant} =
        assistant
        |> Assistant.set_active_config_version_changeset(%{
          active_config_version_id: nl_config_version.id
        })
        |> Repo.update()

      {:ok, first_result} =
        auth_query_gql_by(:clone_assistant, user,
          variables: %{"id" => assistant.id, "version_id" => nl_config_version.id}
        )

      assert first_result.data["cloneAssistant"]["message"] == "Assistant clone initiated"

      {:ok, second_result} =
        auth_query_gql_by(:clone_assistant, user,
          variables: %{"id" => assistant.id, "version_id" => nl_config_version.id}
        )

      _result = second_result.data["cloneAssistant"]

      assert length(all_enqueued(worker: AssistantCloneWorker, prefix: "global")) == 1
    end

    test "returns error when assistant not found", %{manager: user} do
      {:ok, query_data} =
        auth_query_gql_by(:clone_assistant, user, variables: %{"id" => -1})

      result = query_data.data["cloneAssistant"]
      assert result["message"] == nil
      assert [%{"key" => _, "message" => "Resource not found"}] = result["errors"]
    end
  end

  describe "assistant_versions/3" do
    test "returns all versions for an assistant ordered by major/minor version desc", %{
      staff: user,
      organization_id: organization_id
    } do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{name: "Test Assistant", organization_id: organization_id})
        |> Repo.insert()

      # First insert for a new assistant is trigger-assigned major_version: 1, minor_version: 0
      {:ok, v1} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "Prompt v1",
          settings: %{},
          status: :ready
        })
        |> Repo.insert()

      # Second insert (default bump_type: :minor) is trigger-assigned minor_version: 1
      {:ok, _v2} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "Prompt v2",
          settings: %{},
          status: :in_progress
        })
        |> Repo.insert()

      # Third insert (bump_type: :major) is trigger-assigned major_version: 2, minor_version: 0,
      # so ordering must sort by major first, not just minor
      {:ok, _v3} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "Prompt v3",
          settings: %{},
          status: :ready,
          bump_type: :major
        })
        |> Repo.insert()

      {:ok, _assistant} =
        assistant
        |> Assistant.set_active_config_version_changeset(%{active_config_version_id: v1.id})
        |> Repo.update()

      {:ok, query_data} =
        auth_query_gql_by(:assistant_versions, user, variables: %{"assistant_id" => assistant.id})

      versions = query_data.data["assistantVersions"]
      assert length(versions) == 3

      # Ordered newest first by major, then minor
      assert Enum.map(versions, & &1["version_label"]) == ["2.0", "1.1", "1.0"]

      # is_live reflects active_config_version_id
      live_version = Enum.find(versions, & &1["is_live"])
      assert live_version["id"] == to_string(v1.id)

      # versions without a linked knowledge base have no vector_store
      assert Enum.all?(versions, fn v -> is_nil(v["vector_store"]) end)
    end

    test "concurrent inserts for the same assistant get unique, sequential version numbers", %{
      organization_id: organization_id
    } do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{name: "Concurrent Assistant", organization_id: organization_id})
        |> Repo.insert()

      tasks =
        Enum.map(1..5, fn index ->
          Task.async(fn ->
            Repo.put_organization_id(organization_id)

            %AssistantConfigVersion{}
            |> AssistantConfigVersion.changeset(%{
              assistant_id: assistant.id,
              organization_id: organization_id,
              provider: "openai",
              model: "gpt-4o",
              prompt: "Prompt #{index}",
              settings: %{},
              status: :in_progress
            })
            |> Repo.insert()
          end)
        end)

      results = Enum.map(tasks, &Task.await/1)
      assert Enum.all?(results, &match?({:ok, %AssistantConfigVersion{}}, &1))

      version_pairs =
        Enum.map(results, fn {:ok, version} -> {version.major_version, version.minor_version} end)

      assert Enum.uniq(version_pairs) |> length() == 5
      assert Enum.sort(version_pairs) == [{1, 0}, {1, 1}, {1, 2}, {1, 3}, {1, 4}]
    end

    test "returns vector_store linked to each version", %{
      manager: user,
      organization_id: organization_id
    } do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{name: "VS Assistant", organization_id: organization_id})
        |> Repo.insert()

      {:ok, v1} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "Prompt v1",
          settings: %{},
          status: :ready
        })
        |> Repo.insert()

      {:ok, kb} =
        Assistants.create_knowledge_base(%{name: "Test KB", organization_id: organization_id})

      {:ok, kb_version} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: kb.id,
          organization_id: organization_id,
          status: :completed,
          llm_service_id: "vs_test_abc",
          size: 50,
          files: %{}
        })

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert_all("assistant_config_version_knowledge_base_versions", [
        %{
          assistant_config_version_id: v1.id,
          knowledge_base_version_id: kb_version.id,
          organization_id: organization_id,
          inserted_at: now,
          updated_at: now
        }
      ])

      {:ok, _assistant} =
        assistant
        |> Assistant.set_active_config_version_changeset(%{active_config_version_id: v1.id})
        |> Repo.update()

      {:ok, query_data} =
        auth_query_gql_by(:assistant_versions, user, variables: %{"assistant_id" => assistant.id})

      versions = query_data.data["assistantVersions"]
      assert length(versions) == 1

      vs = hd(versions)["vector_store"]
      assert vs != nil
      assert vs["id"] == to_string(kb.id)
      assert vs["knowledge_base_version_id"] == to_string(kb_version.id)
      assert vs["vector_store_id"] == "vs_test_abc"
      assert vs["name"] == "Test KB"
      assert vs["status"] == "completed"
      assert vs["size"] == "50 B"
    end

    test "returns empty versions for a non-existent assistant", %{manager: user} do
      {:ok, query_data} =
        auth_query_gql_by(:assistant_versions, user, variables: %{"assistant_id" => 0})

      versions = query_data.data["assistantVersions"]
      # Absinthe returns a list with nil entries or an empty list when the resolver errors
      assert versions == [] or Enum.all?(versions, &is_nil(&1["id"]))
    end
  end

  describe "set_live_version/3" do
    test "promoting a draft version creates a new major version and repoints the live pointer",
         %{
           staff: user,
           organization_id: organization_id
         } do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{name: "Live Version Test", organization_id: organization_id})
        |> Repo.insert()

      # First insert is trigger-assigned major_version: 1, minor_version: 0 ("1.0")
      {:ok, v1} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "Prompt v1",
          settings: %{},
          status: :ready
        })
        |> Repo.insert()

      {:ok, assistant} =
        assistant
        |> Assistant.set_active_config_version_changeset(%{active_config_version_id: v1.id})
        |> Repo.update()

      # Second insert (default bump_type: :minor) is trigger-assigned "1.1" -- a draft
      {:ok, draft_version} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "Prompt v2",
          settings: %{},
          status: :ready,
          kaapi_version_number: 42
        })
        |> Repo.insert()

      assert AssistantConfigVersion.version_label(v1) == "1.0"
      assert AssistantConfigVersion.version_label(draft_version) == "1.1"

      version_count_before = count_config_versions(assistant.id)

      {:ok, query_data} =
        auth_query_gql_by(:set_live_version, user,
          variables: %{"assistantId" => assistant.id, "versionId" => draft_version.id}
        )

      result = query_data.data["setLiveVersion"]["assistant"]
      assert result["liveVersionLabel"] == "2.0"

      new_live_version_id = String.to_integer(result["activeConfigVersionId"])
      assert new_live_version_id != draft_version.id

      # A brand new row was created for the promoted major version
      assert count_config_versions(assistant.id) == version_count_before + 1

      new_live_version = Repo.get!(AssistantConfigVersion, new_live_version_id)
      assert AssistantConfigVersion.version_label(new_live_version) == "2.0"
      assert new_live_version.status == draft_version.status
      assert new_live_version.kaapi_version_number == draft_version.kaapi_version_number

      updated_assistant = Repo.get!(Assistant, assistant.id)
      assert updated_assistant.active_config_version_id == new_live_version_id

      # The original draft row is untouched, still exists, and is not live
      unchanged_draft_version = Repo.get!(AssistantConfigVersion, draft_version.id)
      assert AssistantConfigVersion.version_label(unchanged_draft_version) == "1.1"
      assert updated_assistant.active_config_version_id != draft_version.id
    end

    test "reactivating an already-major version repoints the live pointer without a new row",
         %{
           staff: user,
           organization_id: organization_id
         } do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{name: "Rollback Test", organization_id: organization_id})
        |> Repo.insert()

      {:ok, v1} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "Prompt v1",
          settings: %{},
          status: :ready,
          bump_type: :major
        })
        |> Repo.insert()

      {:ok, v2} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "Prompt v2",
          settings: %{},
          status: :ready,
          bump_type: :major
        })
        |> Repo.insert()

      {:ok, assistant} =
        assistant
        |> Assistant.set_active_config_version_changeset(%{active_config_version_id: v2.id})
        |> Repo.update()

      assert AssistantConfigVersion.version_label(v1) == "1.0"
      assert AssistantConfigVersion.version_label(v2) == "2.0"

      version_count_before = count_config_versions(assistant.id)

      {:ok, query_data} =
        auth_query_gql_by(:set_live_version, user,
          variables: %{"assistantId" => assistant.id, "versionId" => v1.id}
        )

      result = query_data.data["setLiveVersion"]["assistant"]
      assert result["activeConfigVersionId"] == to_string(v1.id)
      assert result["liveVersionLabel"] == "1.0"

      # Rolling back to an already-published major version does not create a new row
      assert count_config_versions(assistant.id) == version_count_before

      updated_assistant = Repo.get!(Assistant, assistant.id)
      assert updated_assistant.active_config_version_id == v1.id
    end

    test "returns error when version is not in ready status", %{
      manager: user,
      organization_id: organization_id
    } do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Live Version Error Test",
          organization_id: organization_id
        })
        |> Repo.insert()

      {:ok, in_progress_version} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "Draft prompt",
          settings: %{},
          status: :in_progress
        })
        |> Repo.insert()

      {:ok, query_data} =
        auth_query_gql_by(:set_live_version, user,
          variables: %{
            "assistantId" => assistant.id,
            "versionId" => in_progress_version.id
          }
        )

      assert query_data.data["setLiveVersion"] == nil
      assert query_data.errors != nil
    end
  end

  describe "get_file/3" do
    setup :enable_kaapi

    test "returns signed_url on success", %{manager: user} do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: %{
              success: true,
              data: %{
                id: "doc_123",
                fname: "biu-1.pdf",
                signed_url: "https://kaapi-test.s3.amazonaws.com/test/biu-1.pdf"
              }
            }
          }
      end)

      {:ok, query_data} =
        auth_query_gql_by(:get_file, user, variables: %{"file_id" => "doc_123"})

      result = query_data.data["get_file"]
      assert result["file_id"] == "doc_123"
      assert result["filename"] == "biu-1.pdf"
      assert result["signed_url"] == "https://kaapi-test.s3.amazonaws.com/test/biu-1.pdf"
    end

    test "returns a top-level error when kaapi fails", %{manager: user} do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{status: 404, body: %{success: false, error: "Not Found"}}
      end)

      {:ok, query_data} =
        auth_query_gql_by(:get_file, user, variables: %{"file_id" => "missing_doc"})

      assert query_data.data["get_file"] == nil
      assert [error | _] = query_data.errors
      assert error[:message] =~ "status 404"
    end
  end

  defp count_config_versions(assistant_id) do
    AssistantConfigVersion
    |> where([config_version], config_version.assistant_id == ^assistant_id)
    |> Repo.aggregate(:count)
  end

  defp enable_kaapi(%{organization_id: organization_id}) do
    Partners.create_credential(%{
      organization_id: organization_id,
      shortcode: "kaapi",
      keys: %{},
      secrets: %{
        "api_key" => "sk_test_key"
      },
      is_active: true
    })

    :ok
  end
end
