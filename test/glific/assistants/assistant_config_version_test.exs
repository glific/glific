defmodule Glific.Assistants.AssistantConfigVersionTest do
  @moduledoc """
  Tests for AssistantConfigVersion schema and changesets
  """
  use Glific.DataCase

  alias Glific.Assistants.AssistantConfigVersion

  setup %{organization_id: organization_id} do
    valid_attrs = %{
      prompt: "You are a helpful assistant.",
      provider: "openai",
      model: "gpt-4o",
      kaapi_uuid: "kaapi-uuid-12345",
      settings: %{"temperature" => 0.7},
      status: :ready,
      organization_id: organization_id,
      assistant_id: 1
    }

    %{valid_attrs: valid_attrs}
  end

  describe "changeset/2" do
    test "changeset with valid attributes", %{valid_attrs: valid_attrs} do
      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, valid_attrs)

      assert changeset.valid?
      assert get_change(changeset, :prompt) == "You are a helpful assistant."
      assert get_change(changeset, :model) == "gpt-4o"
      assert get_change(changeset, :kaapi_uuid) == "kaapi-uuid-12345"
      assert get_change(changeset, :status) == :ready
      assert get_change(changeset, :settings) == %{"temperature" => 0.7}
    end

    test "changeset without assistant_id returns error", %{valid_attrs: valid_attrs} do
      attrs = Map.delete(valid_attrs, :assistant_id)
      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid? == false
      assert %{assistant_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset without prompt returns error", %{valid_attrs: valid_attrs} do
      attrs = Map.delete(valid_attrs, :prompt)
      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid? == false
      assert %{prompt: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset without model returns error", %{valid_attrs: valid_attrs} do
      attrs = Map.delete(valid_attrs, :model)
      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid? == false
      assert %{model: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset without kaapi_uuid returns error", %{valid_attrs: valid_attrs} do
      attrs = Map.delete(valid_attrs, :kaapi_uuid)
      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid? == false
      assert %{kaapi_uuid: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset uses default settings when not provided", %{valid_attrs: valid_attrs} do
      attrs = Map.delete(valid_attrs, :settings)
      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :settings) == nil
      assert get_field(changeset, :settings) == %{}
    end

    test "changeset uses default provider when not provided", %{valid_attrs: valid_attrs} do
      attrs = Map.delete(valid_attrs, :provider)
      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid?
      assert get_field(changeset, :provider) == "openai"
    end

    test "changeset with optional fields", %{valid_attrs: valid_attrs} do
      attrs =
        valid_attrs
        |> Map.put(:description, "Version 1 of the assistant")
        |> Map.put(:version_number, 1)

      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :description) == "Version 1 of the assistant"
      assert get_change(changeset, :version_number) == 1
    end

    test "changeset with failure_reason when status is failed", %{valid_attrs: valid_attrs} do
      attrs =
        valid_attrs
        |> Map.put(:status, :failed)
        |> Map.put(:failure_reason, "Failed to connect to LLM provider")

      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :status) == :failed
      assert get_change(changeset, :failure_reason) == "Failed to connect to LLM provider"
    end

    test "changeset with all status values", %{valid_attrs: valid_attrs} do
      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, valid_attrs)
      assert changeset.valid?
      assert get_change(changeset, :status) == :ready

      attrs = Map.put(valid_attrs, :status, :failed)
      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :status) == :failed

      attrs = Map.put(valid_attrs, :status, :in_progress)
      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)
      assert changeset.valid?
      assert get_field(changeset, :status) == :in_progress

      attrs = Map.delete(valid_attrs, :status)
      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :status) == nil
      assert get_field(changeset, :status) == :in_progress
    end
  end
end
