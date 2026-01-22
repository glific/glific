defmodule Glific.Assistants.AssistantTest do
  @moduledoc """
  Tests for Assistant, KnowledgeBase, KnowledgeBaseVersion, and AssistantConfigVersion schemas
  """
  use Glific.DataCase

  alias Glific.Assistants.{
    Assistant,
    AssistantConfigVersion,
    KnowledgeBase,
    KnowledgeBaseVersion
  }

  describe "Assistant.changeset/2" do
    @valid_attrs %{
      name: "Test Assistant",
      description: "A helpful assistant for testing"
    }

    @invalid_attrs %{
      name: nil,
      description: "Missing required name"
    }

    test "changeset with valid attributes", %{organization_id: organization_id} do
      attrs = Map.put(@valid_attrs, :organization_id, organization_id)
      changeset = Assistant.changeset(%Assistant{}, attrs)
      assert changeset.valid?
      assert changeset.errors == []
      assert get_change(changeset, :name) == "Test Assistant"
      assert get_change(changeset, :description) == "A helpful assistant for testing"
      assert get_change(changeset, :organization_id) == organization_id
    end

    test "changeset without name returns error", %{organization_id: organization_id} do
      attrs = Map.put(@invalid_attrs, :organization_id, organization_id)
      changeset = Assistant.changeset(%Assistant{}, attrs)

      assert changeset.valid? == false
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset without organization_id returns error" do
      changeset = Assistant.changeset(%Assistant{}, @valid_attrs)

      assert changeset.valid? == false
      assert %{organization_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset with only required fields is valid", %{organization_id: organization_id} do
      attrs = %{
        name: "Minimal Assistant",
        organization_id: organization_id
      }

      changeset = Assistant.changeset(%Assistant{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :name) == "Minimal Assistant"
      assert get_change(changeset, :description) == nil
    end

    test "changeset with empty name returns error", %{organization_id: organization_id} do
      attrs = %{
        name: "",
        organization_id: organization_id
      }

      changeset = Assistant.changeset(%Assistant{}, attrs)

      assert changeset.valid? == false
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "Assistant.set_active_config_version_changeset/2" do
    test "valid changeset with active_config_version_id", %{organization_id: organization_id} do
      assistant = %Assistant{
        id: 1,
        name: "Test Assistant",
        organization_id: organization_id
      }

      attrs = %{active_config_version_id: 123}
      changeset = Assistant.set_active_config_version_changeset(assistant, attrs)

      assert changeset.valid?
      assert get_change(changeset, :active_config_version_id) == 123
    end

    test "invalid changeset without active_config_version_id", %{organization_id: organization_id} do
      assistant = %Assistant{
        id: 1,
        name: "Test Assistant",
        organization_id: organization_id
      }

      attrs = %{}
      changeset = Assistant.set_active_config_version_changeset(assistant, attrs)

      assert changeset.valid? == false
      assert %{active_config_version_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset with nil active_config_version_id returns error", %{
      organization_id: organization_id
    } do
      assistant = %Assistant{
        id: 1,
        name: "Test Assistant",
        organization_id: organization_id
      }

      attrs = %{active_config_version_id: nil}
      changeset = Assistant.set_active_config_version_changeset(assistant, attrs)

      assert changeset.valid? == false
      assert %{active_config_version_id: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "KnowledgeBase.changeset/2" do
    @valid_kb_attrs %{
      name: "Test Knowledge Base"
    }

    test "changeset with valid attributes", %{organization_id: organization_id} do
      attrs = Map.put(@valid_kb_attrs, :organization_id, organization_id)
      changeset = KnowledgeBase.changeset(%KnowledgeBase{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :name) == "Test Knowledge Base"
      assert get_change(changeset, :organization_id) == organization_id
    end

    test "changeset without name returns error", %{organization_id: organization_id} do
      attrs = %{organization_id: organization_id}
      changeset = KnowledgeBase.changeset(%KnowledgeBase{}, attrs)

      assert changeset.valid? == false
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset without organization_id returns error" do
      changeset = KnowledgeBase.changeset(%KnowledgeBase{}, @valid_kb_attrs)

      assert changeset.valid? == false
      assert %{organization_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset with empty name returns error", %{organization_id: organization_id} do
      attrs = %{
        name: "",
        organization_id: organization_id
      }

      changeset = KnowledgeBase.changeset(%KnowledgeBase{}, attrs)

      assert changeset.valid? == false
    end

    test "changeset missing all required fields returns multiple errors" do
      changeset = KnowledgeBase.changeset(%KnowledgeBase{}, %{})

      refute changeset.valid?
      errors = errors_on(changeset)
      assert %{name: ["can't be blank"]} = errors
      assert %{organization_id: ["can't be blank"]} = errors
    end
  end

  describe "KnowledgeBaseVersion.changeset/2" do
    @valid_kbv_attrs %{
      files: %{"file1.pdf" => %{"size" => 1024, "pages" => 10}},
      status: :completed,
      llm_service_id: "vs_abc123"
    }

    test "changeset with valid attributes", %{organization_id: organization_id} do
      attrs =
        @valid_kbv_attrs
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:knowledge_base_id, 1)

      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :files) == %{"file1.pdf" => %{"size" => 1024, "pages" => 10}}
      assert get_change(changeset, :status) == :completed
      assert get_change(changeset, :llm_service_id) == "vs_abc123"
    end

    test "changeset without knowledge_base_id returns error", %{organization_id: organization_id} do
      attrs = Map.put(@valid_kbv_attrs, :organization_id, organization_id)
      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)

      refute changeset.valid?
      assert %{knowledge_base_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset without files returns error", %{organization_id: organization_id} do
      attrs = %{
        organization_id: organization_id,
        knowledge_base_id: 1,
        status: :in_progress,
        llm_service_id: "vs_abc123"
      }

      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)

      assert changeset.valid? == false
      assert %{files: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset without llm_service_id returns error", %{organization_id: organization_id} do
      attrs = %{
        organization_id: organization_id,
        knowledge_base_id: 1,
        files: %{},
        status: :in_progress
      }

      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)

      refute changeset.valid?
      assert %{llm_service_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset with optional fields", %{organization_id: organization_id} do
      attrs =
        @valid_kbv_attrs
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:knowledge_base_id, 1)
        |> Map.put(:size, 2048)
        |> Map.put(:version_number, 1)
        |> Map.put(:kaapi_job_id, "job_xyz789")

      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :size) == 2048
      assert get_change(changeset, :version_number) == 1
      assert get_change(changeset, :kaapi_job_id) == "job_xyz789"
    end

    test "changeset with all status values", %{organization_id: organization_id} do
      base_attrs = %{
        organization_id: organization_id,
        knowledge_base_id: 1,
        files: %{},
        llm_service_id: "vs_abc123"
      }

      changeset =
        KnowledgeBaseVersion.changeset(
          %KnowledgeBaseVersion{},
          Map.put(base_attrs, :status, :completed)
        )

      assert changeset.valid?
      assert get_change(changeset, :status) == :completed

      changeset =
        KnowledgeBaseVersion.changeset(
          %KnowledgeBaseVersion{},
          Map.put(base_attrs, :status, :failed)
        )

      assert changeset.valid?
      assert get_change(changeset, :status) == :failed
    end
  end

  describe "AssistantConfigVersion.changeset/2" do
    @valid_acv_attrs %{
      prompt: "You are a helpful assistant.",
      provider: "openai",
      model: "gpt-4o",
      kaapi_uuid: "kaapi-uuid-12345",
      settings: %{"temperature" => 0.7},
      status: :ready
    }

    test "changeset with valid attributes", %{organization_id: organization_id} do
      attrs =
        @valid_acv_attrs
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:assistant_id, 1)

      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :prompt) == "You are a helpful assistant."
      assert get_change(changeset, :model) == "gpt-4o"
      assert get_change(changeset, :kaapi_uuid) == "kaapi-uuid-12345"
      assert get_change(changeset, :status) == :ready
    end

    test "changeset without assistant_id returns error", %{organization_id: organization_id} do
      attrs = Map.put(@valid_acv_attrs, :organization_id, organization_id)
      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid? == false
      assert %{assistant_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset without prompt returns error", %{organization_id: organization_id} do
      attrs =
        @valid_acv_attrs
        |> Map.delete(:prompt)
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:assistant_id, 1)

      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid? == false
      assert %{prompt: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset without model returns error", %{organization_id: organization_id} do
      attrs =
        @valid_acv_attrs
        |> Map.delete(:model)
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:assistant_id, 1)

      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid? == false
      assert %{model: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset without kaapi_uuid returns error", %{organization_id: organization_id} do
      attrs =
        @valid_acv_attrs
        |> Map.delete(:kaapi_uuid)
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:assistant_id, 1)

      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid? == false
      assert %{kaapi_uuid: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset with optional fields", %{organization_id: organization_id} do
      attrs =
        @valid_acv_attrs
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:assistant_id, 1)
        |> Map.put(:description, "Version 1 of the assistant")
        |> Map.put(:version_number, 1)
        |> Map.put(:failure_reason, nil)

      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :description) == "Version 1 of the assistant"
      assert get_change(changeset, :version_number) == 1
    end

    test "changeset with failure_reason when status is failed", %{
      organization_id: organization_id
    } do
      attrs =
        @valid_acv_attrs
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:assistant_id, 1)
        |> Map.put(:status, :failed)
        |> Map.put(:failure_reason, "Failed to connect to LLM provider")

      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :status) == :failed
      assert get_change(changeset, :failure_reason) == "Failed to connect to LLM provider"
    end

    test "changeset with all status values", %{organization_id: organization_id} do
      base_attrs =
        @valid_acv_attrs
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:assistant_id, 1)

      changeset =
        AssistantConfigVersion.changeset(
          %AssistantConfigVersion{},
          Map.put(base_attrs, :status, :ready)
        )

      assert changeset.valid?
      assert get_change(changeset, :status) == :ready

      changeset =
        AssistantConfigVersion.changeset(
          %AssistantConfigVersion{},
          Map.put(base_attrs, :status, :failed)
        )

      assert changeset.valid?
      assert get_change(changeset, :status) == :failed
    end

    test "changeset with deleted_at for soft delete", %{organization_id: organization_id} do
      deleted_at = DateTime.utc_now()

      attrs =
        @valid_acv_attrs
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:assistant_id, 1)
        |> Map.put(:deleted_at, deleted_at)

      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :deleted_at) == deleted_at
    end
  end
end
