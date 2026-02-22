defmodule GlificWeb.KaapiControllerTest do
  use GlificWeb.ConnCase

  alias Glific.Assistants
  alias Glific.Assistants.Assistant
  alias Glific.Assistants.AssistantConfigVersion
  alias Glific.Assistants.KnowledgeBaseVersion
  alias Glific.Repo

  describe "create_knowledge_base_version/2" do
    setup :setup_knowledge_base

    test "returns 200 and updates knowledge base version on successful callback",
         %{conn: conn, knowledge_base_version: knowledge_base_version} do
      params = %{
        "data" => %{
          "job_id" => knowledge_base_version.kaapi_job_id,
          "status" => "SUCCESSFUL",
          "collection" => %{"llm_service_id" => "vs_updated_789"},
          "error_message" => nil
        }
      }

      conn = post(conn, "/kaapi/knowledge_base_version", params)

      assert response(conn, 200) ==
               "Knowledge base version creation callback handled successfully"

      {:ok, updated_knowledge_base_version} =
        Repo.fetch(KnowledgeBaseVersion, knowledge_base_version.id, skip_organization_id: true)

      assert updated_knowledge_base_version.status == :completed
      assert updated_knowledge_base_version.llm_service_id == "vs_updated_789"
    end

    test "returns 200 and sets failed status on failure callback",
         %{conn: conn, knowledge_base_version: knowledge_base_version} do
      params = %{
        "data" => %{
          "job_id" => knowledge_base_version.kaapi_job_id,
          "status" => "FAILED",
          "collection" => nil,
          "error_message" => "Processing failed"
        }
      }

      conn = post(conn, "/kaapi/knowledge_base_version", params)

      assert response(conn, 200) ==
               "Knowledge base version creation callback handled successfully"

      {:ok, updated_knowledge_base_version} =
        Repo.fetch(KnowledgeBaseVersion, knowledge_base_version.id, skip_organization_id: true)

      assert updated_knowledge_base_version.status == :failed
    end

    test "updates linked assistant config versions on successful callback",
         %{
           conn: conn,
           knowledge_base_version: knowledge_base_version,
           organization_id: organization_id
         } do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{name: "Test Assistant", organization_id: organization_id})
        |> Repo.insert()

      {:ok, assistant_version1} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4",
          prompt: "You are a helpful assistant",
          settings: %{},
          status: :in_progress
        })
        |> Repo.insert()

      {:ok, assistant_version2} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4",
          prompt: "You are a story_teller",
          settings: %{},
          status: :in_progress
        })
        |> Repo.insert()

      Repo.insert_all(
        "assistant_config_version_knowledge_base_versions",
        [
          %{
            assistant_config_version_id: assistant_version1.id,
            knowledge_base_version_id: knowledge_base_version.id,
            organization_id: organization_id,
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now()
          },
          %{
            assistant_config_version_id: assistant_version2.id,
            knowledge_base_version_id: knowledge_base_version.id,
            organization_id: organization_id,
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now()
          }
        ]
      )

      params = %{
        "data" => %{
          "job_id" => knowledge_base_version.kaapi_job_id,
          "status" => "SUCCESSFUL",
          "collection" => %{"llm_service_id" => "vs_new"},
          "error_message" => nil
        }
      }

      conn = post(conn, "/kaapi/knowledge_base_version", params)

      assert response(conn, 200) ==
               "Knowledge base version creation callback handled successfully"

      {:ok, updated_knowledge_base_version} =
        Repo.fetch(KnowledgeBaseVersion, knowledge_base_version.id, skip_organization_id: true)

      updated_knowledge_base_version =
        Repo.preload(updated_knowledge_base_version, :assistant_config_versions)

      assert updated_knowledge_base_version.status == :completed

      for updated_assistant_version <- updated_knowledge_base_version.assistant_config_versions do
        assert updated_assistant_version.status == :ready
      end
    end

    test "updates linked assistant config versions on failure callback",
         %{
           conn: conn,
           knowledge_base_version: knowledge_base_version,
           organization_id: organization_id
         } do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{name: "Test Assistant", organization_id: organization_id})
        |> Repo.insert()

      {:ok, assistant_version1} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4",
          prompt: "You are a helpful assistant",
          settings: %{},
          status: :in_progress
        })
        |> Repo.insert()

      {:ok, assistant_version2} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4",
          prompt: "You are a story_teller",
          settings: %{},
          status: :in_progress
        })
        |> Repo.insert()

      Repo.insert_all(
        "assistant_config_version_knowledge_base_versions",
        [
          %{
            assistant_config_version_id: assistant_version1.id,
            knowledge_base_version_id: knowledge_base_version.id,
            organization_id: organization_id,
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now()
          },
          %{
            assistant_config_version_id: assistant_version2.id,
            knowledge_base_version_id: knowledge_base_version.id,
            organization_id: organization_id,
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now()
          }
        ]
      )

      params = %{
        "data" => %{
          "job_id" => knowledge_base_version.kaapi_job_id,
          "status" => "FAILED",
          "collection" => nil,
          "error_message" => "Processing failed"
        }
      }

      conn = post(conn, "/kaapi/knowledge_base_version", params)

      assert response(conn, 200) ==
               "Knowledge base version creation callback handled successfully"

      {:ok, updated_knowledge_base_version} =
        Repo.fetch(KnowledgeBaseVersion, knowledge_base_version.id, skip_organization_id: true)

      updated_knowledge_base_version =
        Repo.preload(updated_knowledge_base_version, :assistant_config_versions)

      assert updated_knowledge_base_version.status == :failed

      for updated_assistant_version <- updated_knowledge_base_version.assistant_config_versions do
        assert updated_assistant_version.status == :failed
        assert updated_assistant_version.failure_reason == "Processing failed"
      end
    end

    test "returns 200 when job_id is not found",
         %{conn: conn} do
      params = %{
        "data" => %{
          "job_id" => "nonexistent_job",
          "status" => "SUCCESSFUL",
          "collection" => %{"llm_service_id" => "vs_123"},
          "error_message" => nil
        }
      }

      conn = post(conn, "/kaapi/knowledge_base_version", params)

      assert response(conn, 200) ==
               "Knowledge base version creation callback handled successfully"
    end

    test "does not update already failed knowledge base version",
         %{conn: conn, knowledge_base_version: knowledge_base_version} do
      {:ok, _} =
        Assistants.update_knowledge_base_version(knowledge_base_version, %{status: :failed})

      params = %{
        "data" => %{
          "job_id" => knowledge_base_version.kaapi_job_id,
          "status" => "SUCCESSFUL",
          "collection" => %{"llm_service_id" => "vs_new"},
          "error_message" => nil
        }
      }

      conn = post(conn, "/kaapi/knowledge_base_version", params)

      assert response(conn, 200) ==
               "Knowledge base version creation callback handled successfully"

      {:ok, updated} =
        Repo.fetch(KnowledgeBaseVersion, knowledge_base_version.id, skip_organization_id: true)

      assert updated.status == :failed
      assert updated.updated_at == knowledge_base_version.updated_at
    end
  end

  defp setup_knowledge_base(%{organization_id: organization_id}) do
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
        llm_service_id: "temp_vs_12345",
        kaapi_job_id: "job_abc123",
        size: 100
      })

    %{
      knowledge_base_version: knowledge_base_version,
      organization_id: organization_id
    }
  end
end
