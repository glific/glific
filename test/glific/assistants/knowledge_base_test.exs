defmodule Glific.Assistants.KnowledgeBaseTest do
  @moduledoc """
  Tests for KnowledgeBase schema and changesets
  """
  use Glific.DataCase

  alias Glific.Assistants.KnowledgeBase

  setup %{organization_id: organization_id} do
    valid_attrs = %{
      name: "Test Knowledge Base",
      organization_id: organization_id
    }

    %{valid_attrs: valid_attrs}
  end

  describe "changeset/2" do
    test "changeset with valid attributes", %{valid_attrs: valid_attrs} do
      changeset = KnowledgeBase.changeset(%KnowledgeBase{}, valid_attrs)

      assert changeset.valid?
      assert get_change(changeset, :name) == "Test Knowledge Base"
    end

    test "changeset without name returns error", %{valid_attrs: valid_attrs} do
      attrs = Map.delete(valid_attrs, :name)
      changeset = KnowledgeBase.changeset(%KnowledgeBase{}, attrs)

      assert changeset.valid? == false
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset without organization_id returns error", %{valid_attrs: valid_attrs} do
      attrs = Map.delete(valid_attrs, :organization_id)
      changeset = KnowledgeBase.changeset(%KnowledgeBase{}, attrs)

      assert changeset.valid? == false
      assert %{organization_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset with empty name returns error", %{valid_attrs: valid_attrs} do
      attrs = Map.put(valid_attrs, :name, "")
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
