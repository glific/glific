defmodule Glific.Assistants.AssistantTest do
  @moduledoc """
  Tests for Assistant schema and changesets
  """
  use Glific.DataCase

  alias Glific.Assistants.Assistant

  @valid_attrs %{
    name: "Test Assistant",
    description: "A helpful assistant for testing"
  }

  @invalid_attrs %{
    name: nil,
    description: "Missing required name"
  }
  describe "changeset/2" do
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

    test "set_active_config_version_changeset with valid active_config_version_id" do
      assistant = %Assistant{id: 1, name: "Test Assistant"}
      attrs = %{active_config_version_id: 2}

      changeset = Assistant.set_active_config_version_changeset(assistant, attrs)

      assert changeset.valid?
      assert get_change(changeset, :active_config_version_id) == 2
    end
  end
end
