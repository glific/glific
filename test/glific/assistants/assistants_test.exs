defmodule Glific.AssistantsTest do
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

    # Link config version to knowledge base version via join table
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

    assistant = List.first(assistants)
    assert assistant["name"] == "Test Assistant"
    assert assistant["assistant_id"] == "asst_unified_123"
    assert assistant["temperature"] == 0.7
    assert assistant["status"] == "ready"
    assert assistant["new_version_in_progress"] == false
  end

  test "list assistants with unified API includes vector store from knowledge base", %{
    user: user
  } do
    {_assistant, config} = create_unified_assistant(%{organization_id: user.organization_id})

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

    assistant = List.first(result.data["Assistants"])
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
        status: :ready
      })

    # Create another config version in progress (not the active one)
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

    assistant_data = List.first(result.data["Assistants"])
    assert assistant_data["new_version_in_progress"] == true
  end

  test "list assistants filters by name", %{user: user} do
    create_unified_assistant(%{
      organization_id: user.organization_id,
      name: "Alpha Bot"
    })

    create_unified_assistant(%{
      organization_id: user.organization_id,
      name: "Beta Bot",
      kaapi_uuid: "asst_unified_beta"
    })

    {:ok, result} =
      auth_query_gql_by(:assistants, user,
        variables: %{
          "filter" => %{"name" => "Alpha"}
        }
      )

    assert length(result.data["Assistants"]) == 1
    assert List.first(result.data["Assistants"])["name"] == "Alpha Bot"
  end

  test "list assistants supports pagination opts", %{user: user} do
    create_unified_assistant(%{
      organization_id: user.organization_id,
      name: "First",
      kaapi_uuid: "asst_1"
    })

    create_unified_assistant(%{
      organization_id: user.organization_id,
      name: "Second",
      kaapi_uuid: "asst_2"
    })

    {:ok, result} =
      auth_query_gql_by(:assistants, user,
        variables: %{
          "opts" => %{"limit" => 1}
        }
      )

    assert length(result.data["Assistants"]) == 1
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

    assistant = List.first(result.data["Assistants"])

    # Top-level assistant fields
    assert is_binary(assistant["id"])
    assert assistant["name"] == "Full Response Bot"
    assert assistant["assistant_id"] == "asst_full_resp"
    assert assistant["temperature"] == 0.3
    assert assistant["status"] == "ready"
    assert assistant["new_version_in_progress"] == false
    assert is_binary(assistant["inserted_at"])
    assert is_binary(assistant["updated_at"])

    # Vector store fields
    vs = assistant["vector_store"]
    assert vs != nil
    assert is_binary(vs["id"])
    assert vs["vector_store_id"] == "vs_full_resp"
    assert vs["name"] == "Coding KB"
    assert vs["legacy"] == false
    assert vs["status"] == "completed"

    # Files within vector store
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

    # All assistant fields present and correct
    assert is_binary(data["id"])
    assert data["name"] == "Show Bot"
    assert data["assistant_id"] == "asst_show_bot"
    assert data["temperature"] == 1.0
    assert data["status"] == "ready"
    assert data["new_version_in_progress"] == false
    assert is_binary(data["inserted_at"])
    assert is_binary(data["updated_at"])

    # Vector store fully populated
    vs = data["vector_store"]
    assert vs != nil
    assert is_binary(vs["id"])
    assert vs["vector_store_id"] == "vs_show_bot"
    assert vs["name"] == "Support KB"
    assert vs["legacy"] == false
    assert vs["status"] == "completed"

    # Single file
    assert length(vs["files"]) == 1
    file = List.first(vs["files"])
    assert file["id"] == "file_single"
    assert file["name"] == "faq.pdf"
    assert file["uploaded_at"] == "2025-05-01T08:30:00Z"
  end

  test "assistant status maps correctly for all config version statuses", %{user: user} do
    # Test :in_progress status
    {assistant_ip, _} =
      create_unified_assistant(%{
        organization_id: user.organization_id,
        name: "In Progress Bot",
        kaapi_uuid: "asst_ip",
        status: :in_progress
      })

    {:ok, result} =
      auth_query_gql_by(:assistant, user, variables: %{"id" => assistant_ip.id})

    assert result.data["assistant"]["assistant"]["status"] == "in_progress"

    # Test :failed status
    {assistant_f, _} =
      create_unified_assistant(%{
        organization_id: user.organization_id,
        name: "Failed Bot",
        kaapi_uuid: "asst_failed",
        status: :failed
      })

    {:ok, result} =
      auth_query_gql_by(:assistant, user, variables: %{"id" => assistant_f.id})

    assert result.data["assistant"]["assistant"]["status"] == "failed"

    # Test :ready status
    {assistant_r, _} =
      create_unified_assistant(%{
        organization_id: user.organization_id,
        name: "Ready Bot",
        kaapi_uuid: "asst_ready",
        status: :ready
      })

    {:ok, result} =
      auth_query_gql_by(:assistant, user, variables: %{"id" => assistant_r.id})

    assert result.data["assistant"]["assistant"]["status"] == "ready"
  end

  test "vector store status maps correctly from knowledge base version status", %{user: user} do
    # Test :in_progress KB status
    {_assistant1, config1} =
      create_unified_assistant(%{
        organization_id: user.organization_id,
        name: "KB InProgress Bot",
        kaapi_uuid: "asst_kb_ip"
      })

    create_knowledge_base_for_config(config1, %{
      organization_id: user.organization_id,
      kb_name: "Processing KB",
      kb_status: :in_progress,
      llm_service_id: "vs_kb_ip"
    })

    # Test :failed KB status
    {_assistant2, config2} =
      create_unified_assistant(%{
        organization_id: user.organization_id,
        name: "KB Failed Bot",
        kaapi_uuid: "asst_kb_f"
      })

    create_knowledge_base_for_config(config2, %{
      organization_id: user.organization_id,
      kb_name: "Failed KB",
      kb_status: :failed,
      llm_service_id: "vs_kb_f"
    })

    {:ok, result} =
      auth_query_gql_by(:assistants, user, variables: %{})

    assistants = result.data["Assistants"]

    ip_bot =
      Enum.find(assistants, fn a -> a["name"] == "KB InProgress Bot" end)

    assert ip_bot["vector_store"]["status"] == "in_progress"

    failed_bot =
      Enum.find(assistants, fn a -> a["name"] == "KB Failed Bot" end)

    assert failed_bot["vector_store"]["status"] == "failed"
  end

  test "model and instructions are mapped from config version", %{user: user} do
    {assistant, _config} =
      create_unified_assistant(%{
        organization_id: user.organization_id,
        name: "Custom Model Bot",
        kaapi_uuid: "asst_custom",
        model: "gpt-4-turbo",
        prompt: "You are a translation expert. Always respond in French."
      })

    {:ok, result} =
      auth_query_gql_by(:assistant, user, variables: %{"id" => assistant.id})

    data = result.data["assistant"]["assistant"]
    assert data["model"] == nil
    assert data["assistant_id"] == "asst_custom"
    assert data["temperature"] == 0.7
  end

  test "new_version_in_progress is false when active version itself is in_progress", %{
    user: user
  } do
    # If the ONLY config version is the active one and it's in_progress,
    # new_version_in_progress should be false (there's no OTHER version in progress)
    {assistant, _config} =
      create_unified_assistant(%{
        organization_id: user.organization_id,
        name: "Self InProgress Bot",
        kaapi_uuid: "asst_self_ip",
        status: :in_progress
      })

    {:ok, result} =
      auth_query_gql_by(:assistant, user, variables: %{"id" => assistant.id})

    data = result.data["assistant"]["assistant"]
    assert data["status"] == "in_progress"
    assert data["new_version_in_progress"] == false
  end

  test "vector store is nil when config version has no knowledge base", %{user: user} do
    {assistant, _config} =
      create_unified_assistant(%{
        organization_id: user.organization_id,
        name: "No KB Bot",
        kaapi_uuid: "asst_no_kb"
      })

    {:ok, result} =
      auth_query_gql_by(:assistant, user, variables: %{"id" => assistant.id})

    data = result.data["assistant"]["assistant"]
    assert data["name"] == "No KB Bot"
    assert data["status"] == "ready"
    assert data["vector_store"] == nil
  end

  test "assistant without active config version returns nil fields", %{user: user} do
    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{
        name: "Empty Assistant",
        organization_id: user.organization_id
      })
      |> Repo.insert()

    {:ok, result} =
      auth_query_gql_by(:assistant, user, variables: %{"id" => assistant.id})

    data = result.data["assistant"]["assistant"]
    assert data["name"] == "Empty Assistant"
    assert data["assistant_id"] == nil
    assert data["status"] == nil
    assert data["temperature"] == nil
    assert data["vector_store"] == nil
    assert data["new_version_in_progress"] == false
  end
end
