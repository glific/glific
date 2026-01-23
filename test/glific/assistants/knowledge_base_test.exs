defmodule Glific.Assistants.KnowledgeBaseTest do
  @moduledoc """
  Tests for KnowledgeBase schema and changesets
  """
  use Glific.DataCase

  alias Glific.Assistants.KnowledgeBase

  @valid_attrs %{
    name: "Test Knowledge Base"
  }

  describe "KnowledgeBase.changeset/2" do
    test "changeset with valid attributes", %{organization_id: organization_id} do
      attrs = Map.put(@valid_attrs, :organization_id, organization_id)
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
      changeset = KnowledgeBase.changeset(%KnowledgeBase{}, @valid_attrs)

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
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset missing all required fields returns multiple errors" do
      changeset = KnowledgeBase.changeset(%KnowledgeBase{}, %{})

      refute changeset.valid?
      errors = errors_on(changeset)
      assert %{name: ["can't be blank"]} = errors
      assert %{organization_id: ["can't be blank"]} = errors
    end
  end
end
