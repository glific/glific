defmodule Glific.Assistants.KnowledgeBaseVersionTest do
  @moduledoc """
  Tests for KnowledgeBaseVersion schema and changesets
  """
  use Glific.DataCase

  alias Glific.Assistants.KnowledgeBaseVersion

  require Glific.Enums

  describe "KnowledgeBaseVersion.changeset/2" do
    @valid_attrs %{
      files: %{"file1.pdf" => %{"size" => 1024, "pages" => 10}},
      status: :completed,
      llm_service_id: "vs_abc123"
    }

    test "changeset with valid attributes", %{organization_id: organization_id} do
      attrs =
        @valid_attrs
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:knowledge_base_id, 1)

      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :files) == %{"file1.pdf" => %{"size" => 1024, "pages" => 10}}
      assert get_change(changeset, :status) == :completed
      assert get_change(changeset, :llm_service_id) == "vs_abc123"
    end

    test "changeset without knowledge_base_id returns error", %{organization_id: organization_id} do
      attrs = Map.put(@valid_attrs, :organization_id, organization_id)
      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)

      assert changeset.valid? == false
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

      assert changeset.valid? == false
      assert %{llm_service_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset with optional fields", %{organization_id: organization_id} do
      attrs =
        @valid_attrs
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
          Map.put(base_attrs, :status, :in_progress)
        )

      assert changeset.valid?
      assert get_field(changeset, :status) == :in_progress

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
end
