defmodule Glific.Assistants.KnowledgeBaseVersionTest do
  @moduledoc """
  Tests for KnowledgeBaseVersion schema and changesets
  """
  use Glific.DataCase

  alias Glific.Assistants.KnowledgeBaseVersion

  setup %{organization_id: organization_id} do
    valid_attrs = %{
      files: %{"file1.pdf" => %{"size" => 1024, "pages" => 10}},
      status: :completed,
      llm_service_id: "vs_abc123",
      organization_id: organization_id,
      knowledge_base_id: 1
    }

    %{valid_attrs: valid_attrs}
  end

  describe "changeset/2" do
    test "changeset with valid attributes", %{valid_attrs: valid_attrs} do
      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, valid_attrs)

      assert changeset.valid?
      assert get_change(changeset, :files) == %{"file1.pdf" => %{"size" => 1024, "pages" => 10}}
      assert get_change(changeset, :status) == :completed
      assert get_change(changeset, :llm_service_id) == "vs_abc123"
    end

    test "changeset without knowledge_base_id returns error", %{valid_attrs: valid_attrs} do
      attrs = Map.delete(valid_attrs, :knowledge_base_id)
      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)

      assert changeset.valid? == false
      assert %{knowledge_base_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset without files returns error", %{valid_attrs: valid_attrs} do
      attrs = Map.delete(valid_attrs, :files)
      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)

      assert changeset.valid? == false
      assert %{files: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset without llm_service_id returns error", %{valid_attrs: valid_attrs} do
      attrs = Map.delete(valid_attrs, :llm_service_id)
      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)

      assert changeset.valid? == false
      assert %{llm_service_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset with optional fields", %{valid_attrs: valid_attrs} do
      attrs =
        valid_attrs
        |> Map.put(:size, 2048)
        |> Map.put(:version_number, 1)
        |> Map.put(:kaapi_job_id, "job_xyz789")

      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :size) == 2048
      assert get_change(changeset, :version_number) == 1
      assert get_change(changeset, :kaapi_job_id) == "job_xyz789"
    end

    test "changeset with all status values", %{valid_attrs: valid_attrs} do
      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, valid_attrs)
      assert changeset.valid?
      assert get_change(changeset, :status) == :completed

      attrs = Map.put(valid_attrs, :status, :failed)
      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :status) == :failed

      attrs = Map.put(valid_attrs, :status, :in_progress)
      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)
      assert changeset.valid?
      assert get_field(changeset, :status) == :in_progress

      attrs = Map.delete(valid_attrs, :status)
      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :status) == nil
      assert get_field(changeset, :status) == :in_progress
    end
  end
end
