defmodule Glific.Assistants.AssistantTest do
  @moduledoc """
  Tests for Assistant schema and changesets
  """
  use Glific.DataCase

  alias Glific.{
    Assistants.Assistant,
    Repo
  }

  setup %{organization_id: organization_id} do
    valid_attrs = %{
      name: "Test Assistant",
      description: "A helpful assistant for testing",
      organization_id: organization_id,
      kaapi_uuid: "asst_123"
    }

    %{valid_attrs: valid_attrs}
  end

  describe "changeset/2" do
    test "changeset with valid attributes", %{valid_attrs: valid_attrs} do
      changeset = Assistant.changeset(%Assistant{}, valid_attrs)

      assert changeset.valid?
      assert changeset.errors == []
      assert get_change(changeset, :name) == "Test Assistant"
      assert get_change(changeset, :description) == "A helpful assistant for testing"
    end

    test "changeset without name returns error", %{valid_attrs: valid_attrs} do
      attrs = Map.delete(valid_attrs, :name)
      changeset = Assistant.changeset(%Assistant{}, attrs)

      assert changeset.valid? == false
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset without organization_id returns error", %{valid_attrs: valid_attrs} do
      attrs = Map.delete(valid_attrs, :organization_id)
      changeset = Assistant.changeset(%Assistant{}, attrs)

      assert changeset.valid? == false
      assert %{organization_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset with only required fields is valid", %{valid_attrs: valid_attrs} do
      attrs = Map.delete(valid_attrs, :description)
      changeset = Assistant.changeset(%Assistant{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :name) == "Test Assistant"
      assert get_change(changeset, :description) == nil
    end

    test "changeset with empty name returns error", %{valid_attrs: valid_attrs} do
      attrs = Map.put(valid_attrs, :name, "")
      changeset = Assistant.changeset(%Assistant{}, attrs)

      assert changeset.valid? == false
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "set_active_config_version_changeset/2" do
    test "valid changeset with active_config_version_id", %{valid_attrs: valid_attrs} do
      assistant = struct(Assistant, valid_attrs)

      changeset =
        Assistant.set_active_config_version_changeset(assistant, %{active_config_version_id: 123})

      assert changeset.valid?
      assert get_change(changeset, :active_config_version_id) == 123
    end

    test "invalid changeset without active_config_version_id", %{valid_attrs: valid_attrs} do
      assistant = struct(Assistant, valid_attrs)
      changeset = Assistant.set_active_config_version_changeset(assistant, %{})

      assert changeset.valid? == false
      assert %{active_config_version_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset with nil active_config_version_id returns error", %{valid_attrs: valid_attrs} do
      assistant = struct(Assistant, valid_attrs)

      changeset =
        Assistant.set_active_config_version_changeset(assistant, %{active_config_version_id: nil})

      assert changeset.valid? == false
      assert %{active_config_version_id: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "ExAudit tracking" do
    test "assistant should be audited with ExAudit", %{organization_id: organization_id} do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Audit Test Assistant",
          description: "Testing audit tracking",
          kaapi_uuid: "asst_123",
          organization_id: organization_id
        })
        |> Repo.insert()

      [created_history] = Repo.history(assistant, skip_organization_id: true)
      assert created_history.action == :created
      assert :name in Map.keys(created_history.patch)

      {:ok, updated_assistant} =
        assistant
        |> Assistant.changeset(%{name: "Updated Audit Test Assistant"})
        |> Repo.update()

      history = Repo.history(updated_assistant, skip_organization_id: true)
      assert length(history) == 2
      update_history = List.last(history)
      assert update_history.action == :updated
      assert :name in Map.keys(update_history.patch)
    end
  end
end
