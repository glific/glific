defmodule GlificWeb.Schema.UnifiedAssistantsTest do
  @moduledoc """
  Tests for unified API assistants
  """

  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Assistants.KnowledgeBase,
    Assistants.KnowledgeBaseVersion,
    Repo
  }

  load_gql(
    :assistants,
    GlificWeb.Schema,
    "assets/gql/filesearch/list_assistants.gql"
  )

  load_gql(
    :assistant,
    GlificWeb.Schema,
    "assets/gql/filesearch/assistant_by_id.gql"
  )

  setup do
    FunWithFlags.enable(:unified_api_enabled,
      for_actor: %{organization_id: 1}
    )

    :ok
  end

  defp create_unified_assistant(attrs) do
    org_id = attrs[:organization_id] || 1

    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{
        name: attrs[:name] || "Test Assistant",
        organization_id: org_id
      })
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        provider: "openai",
        model: attrs[:model] || "gpt-4o",
        kaapi_uuid: attrs[:kaapi_uuid] || "asst_unified_123",
        prompt: attrs[:prompt] || "You are a helpful assistant",
        settings: attrs[:settings] || %{"temperature" => 0.7},
        status: attrs[:status] || :ready,
        organization_id: org_id
      })
      |> Repo.insert()

    {:ok, assistant} =
      assistant
      |> Assistant.set_active_config_version_changeset(%{
        active_config_version_id: config_version.id
      })
      |> Repo.update()

    {assistant, config_version}
  end

  defp create_knowledge_base_for_config(config_version, attrs) do
    org_id = attrs[:organization_id] || 1

    {:ok, kb} =
      %KnowledgeBase{}
      |> KnowledgeBase.changeset(%{
        name: attrs[:kb_name] || "Test KB",
        organization_id: org_id
      })
      |> Repo.insert()

    {:ok, kbv} =
      %KnowledgeBaseVersion{}
      |> KnowledgeBaseVersion.changeset(%{
        knowledge_base_id: kb.id,
        organization_id: org_id,
        files: attrs[:files] || %{},
        status: attrs[:kb_status] || :completed,
        llm_service_id: attrs[:llm_service_id] || "vs_unified_456",
        size: attrs[:size] || 1024
      })
      |> Repo.insert()

    Repo.insert_all("assistant_config_version_knowledge_base_versions", [
      %{
        assistant_config_version_id: config_version.id,
        knowledge_base_version_id: kbv.id,
        organization_id: org_id,
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
    ])

    {kb, kbv}
  end

  test "list assistants with unified API returns transformed data", %{user: user} do
    {_assistant, _config} = create_unified_assistant(%{organization_id: user.organization_id})

    {:ok, result} =
      auth_query_gql_by(:assistants, user, variables: %{})

    assistants = result.data["Assistants"]
    assert length(assistants) >= 1

    assistant = Enum.find(assistants, fn a -> a["assistant_id"] == "asst_unified_123" end)
    assert assistant != nil
    assert assistant["name"] == "Test Assistant"
    assert assistant["assistant_id"] == "asst_unified_123"
    assert assistant["temperature"] == 0.7
    assert assistant["status"] == "ready"
    assert assistant["new_version_in_progress"] == false
  end

  test "list assistants with unified API includes vector store from knowledge base", %{
    user: user
  } do
    {_assistant, config} =
      create_unified_assistant(%{
        organization_id: user.organization_id,
        name: "KB Test Bot",
        kaapi_uuid: "asst_kb_test"
      })

    files = %{
      "file_1" => %{"filename" => "test.pdf", "uploaded_at" => "2025-01-01T00:00:00Z"}
    }

    {_kb, _kbv} =
      create_knowledge_base_for_config(config, %{
        organization_id: user.organization_id,
        kb_name: "My KB",
        files: files,
        llm_service_id: "vs_kb_789"
      })

    {:ok, result} =
      auth_query_gql_by(:assistants, user, variables: %{})

    assistant = Enum.find(result.data["Assistants"], fn a -> a["assistant_id"] == "asst_kb_test" end)
    assert assistant != nil

    vs = assistant["vector_store"]
    assert vs != nil
    assert vs["name"] == "My KB"
    assert vs["vector_store_id"] == "vs_kb_789"
    assert vs["legacy"] == false
    assert length(vs["files"]) == 1
  end

  test "get assistant with unified API returns transformed data", %{user: user} do
    {assistant, config} = create_unified_assistant(%{organization_id: user.organization_id})

    files = %{
      "file_1" => %{"filename" => "doc.pdf", "uploaded_at" => "2025-06-01T00:00:00Z"}
    }

    {_kb, _kbv} =
      create_knowledge_base_for_config(config, %{
        organization_id: user.organization_id,
        kb_name: "Doc KB",
        files: files,
        llm_service_id: "vs_doc_123"
      })

    {:ok, result} =
      auth_query_gql_by(:assistant, user, variables: %{"id" => assistant.id})

    data = result.data["assistant"]["assistant"]
    assert data["name"] == "Test Assistant"
    assert data["assistant_id"] == "asst_unified_123"
    assert data["status"] == "ready"
    assert data["new_version_in_progress"] == false

    vs = data["vector_store"]
    assert vs["name"] == "Doc KB"
    assert vs["vector_store_id"] == "vs_doc_123"
    assert vs["legacy"] == false
  end

  test "new_version_in_progress is true when non-active config version is in progress", %{
    user: user
  } do
    {assistant, _config} =
      create_unified_assistant(%{
        organization_id: user.organization_id,
        name: "Version Progress Bot",
        kaapi_uuid: "asst_version_progress",
        status: :ready
      })

    {:ok, _in_progress_cv} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        provider: "openai",
        model: "gpt-4o",
        kaapi_uuid: "asst_unified_456",
        prompt: "New version prompt",
        settings: %{"temperature" => 0.5},
        status: :in_progress,
        organization_id: user.organization_id
      })
      |> Repo.insert()

    {:ok, result} =
      auth_query_gql_by(:assistants, user, variables: %{})

    assistant_data =
      Enum.find(result.data["Assistants"], fn a -> a["assistant_id"] == "asst_version_progress" end)

    assert assistant_data != nil
    assert assistant_data["new_version_in_progress"] == true
  end

  test "list API returns complete response structure with all fields", %{user: user} do
    {_assistant, config} =
      create_unified_assistant(%{
        organization_id: user.organization_id,
        name: "Full Response Bot",
        kaapi_uuid: "asst_full_resp",
        model: "gpt-4o-mini",
        prompt: "You are a coding assistant",
        settings: %{"temperature" => 0.3},
        status: :ready
      })

    files = %{
      "file_abc" => %{"filename" => "guide.pdf", "uploaded_at" => "2025-03-15T10:00:00Z"},
      "file_xyz" => %{"filename" => "notes.txt", "uploaded_at" => "2025-03-16T12:00:00Z"}
    }

    {_kb, _kbv} =
      create_knowledge_base_for_config(config, %{
        organization_id: user.organization_id,
        kb_name: "Coding KB",
        files: files,
        llm_service_id: "vs_full_resp",
        kb_status: :completed,
        size: 52_428
      })

    {:ok, result} =
      auth_query_gql_by(:assistants, user, variables: %{})

    assistant =
      Enum.find(result.data["Assistants"], fn a -> a["assistant_id"] == "asst_full_resp" end)

    assert assistant != nil
    assert is_binary(assistant["id"])
    assert assistant["name"] == "Full Response Bot"
    assert assistant["assistant_id"] == "asst_full_resp"
    assert assistant["temperature"] == 0.3
    assert assistant["status"] == "ready"
    assert assistant["new_version_in_progress"] == false
    assert is_binary(assistant["inserted_at"])
    assert is_binary(assistant["updated_at"])

    vs = assistant["vector_store"]
    assert vs != nil
    assert is_binary(vs["id"])
    assert vs["vector_store_id"] == "vs_full_resp"
    assert vs["name"] == "Coding KB"
    assert vs["legacy"] == false
    assert vs["status"] == "completed"

    assert length(vs["files"]) == 2
    file_names = Enum.map(vs["files"], & &1["name"]) |> Enum.sort()
    assert file_names == ["guide.pdf", "notes.txt"]

    Enum.each(vs["files"], fn file ->
      assert is_binary(file["id"])
      assert is_binary(file["name"])
      assert is_binary(file["uploaded_at"])
    end)
  end

  test "get API returns complete response structure with all fields", %{user: user} do
    {assistant, config} =
      create_unified_assistant(%{
        organization_id: user.organization_id,
        name: "Show Bot",
        kaapi_uuid: "asst_show_bot",
        model: "gpt-4o",
        prompt: "You are a support agent",
        settings: %{"temperature" => 1.0},
        status: :ready
      })

    files = %{
      "file_single" => %{"filename" => "faq.pdf", "uploaded_at" => "2025-05-01T08:30:00Z"}
    }

    {_kb, _kbv} =
      create_knowledge_base_for_config(config, %{
        organization_id: user.organization_id,
        kb_name: "Support KB",
        files: files,
        llm_service_id: "vs_show_bot",
        kb_status: :completed,
        size: 10_240
      })

    {:ok, result} =
      auth_query_gql_by(:assistant, user, variables: %{"id" => assistant.id})

    data = result.data["assistant"]["assistant"]

    assert is_binary(data["id"])
    assert data["name"] == "Show Bot"
    assert data["assistant_id"] == "asst_show_bot"
    assert data["temperature"] == 1.0
    assert data["status"] == "ready"
    assert data["new_version_in_progress"] == false
    assert is_binary(data["inserted_at"])
    assert is_binary(data["updated_at"])

    vs = data["vector_store"]
    assert vs != nil
    assert is_binary(vs["id"])
    assert vs["vector_store_id"] == "vs_show_bot"
    assert vs["name"] == "Support KB"
    assert vs["legacy"] == false
    assert vs["status"] == "completed"

    assert length(vs["files"]) == 1
    file = List.first(vs["files"])
    assert file["id"] == "file_single"
    assert file["name"] == "faq.pdf"
    assert file["uploaded_at"] == "2025-05-01T08:30:00Z"
  end
end
