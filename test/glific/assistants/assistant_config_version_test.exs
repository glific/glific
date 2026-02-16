defmodule Glific.Assistants.AssistantConfigVersionTest do
  @moduledoc """
  Tests for AssistantConfigVersion schema and changesets
  """
  use Glific.DataCase

  alias Glific.{
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Repo
  }

  setup %{organization_id: organization_id} do
    valid_attrs = %{
      prompt: "You are a helpful assistant.",
      provider: "openai",
      model: "gpt-4o",
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

  describe "ExAudit tracking" do
    test "assistant_config_version should be audited with ExAudit",
         %{organization_id: organization_id} do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Config Version Test Assistant",
          kaapi_uuid: "test-uuid",
          organization_id: organization_id
        })
        |> Repo.insert()

      {:ok, config_version} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          prompt: "You are a helpful assistant",
          provider: "openai",
          model: "gpt-4o",
          settings: %{"temperature" => 0.7},
          status: :ready,
          organization_id: organization_id
        })
        |> Repo.insert()

      [created_history] = Repo.history(config_version, skip_organization_id: true)
      assert created_history.action == :created
      assert :prompt in Map.keys(created_history.patch)
      assert :model in Map.keys(created_history.patch)

      {:ok, updated_config_version} =
        config_version
        |> AssistantConfigVersion.changeset(%{prompt: "You are an updated helpful assistant"})
        |> Repo.update()

      history = Repo.history(updated_config_version, skip_organization_id: true)
      assert length(history) == 2
      update_history = List.last(history)
      assert update_history.action == :updated
      assert :prompt in Map.keys(update_history.patch)
    end
  end
end
