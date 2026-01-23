defmodule Glific.Assistants.AssistantConfigVersionTest do
  @moduledoc """
  Tests for AssistantConfigVersion schema and changesets
  """
  use Glific.DataCase

  alias Glific.Assistants.AssistantConfigVersion

  describe "AssistantConfigVersion.changeset/2" do
    @valid_attrs %{
      prompt: "You are a helpful assistant.",
      provider: "openai",
      model: "gpt-4o",
      kaapi_uuid: "kaapi-uuid-12345",
      settings: %{"temperature" => 0.7},
      status: :ready
    }

    test "changeset with valid attributes", %{organization_id: organization_id} do
      attrs =
        @valid_attrs
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:assistant_id, 1)

      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :prompt) == "You are a helpful assistant."
      assert get_change(changeset, :model) == "gpt-4o"
      assert get_change(changeset, :kaapi_uuid) == "kaapi-uuid-12345"
      assert get_change(changeset, :status) == :ready
      assert get_change(changeset, :settings) == %{"temperature" => 0.7}
    end

    test "changeset without assistant_id returns error", %{organization_id: organization_id} do
      attrs = Map.put(@valid_attrs, :organization_id, organization_id)
      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid? == false
      assert %{assistant_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset without prompt returns error", %{organization_id: organization_id} do
      attrs =
        @valid_attrs
        |> Map.delete(:prompt)
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:assistant_id, 1)

      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid? == false
      assert %{prompt: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset without model returns error", %{organization_id: organization_id} do
      attrs =
        @valid_attrs
        |> Map.delete(:model)
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:assistant_id, 1)

      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid? == false
      assert %{model: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset without kaapi_uuid returns error", %{organization_id: organization_id} do
      attrs =
        @valid_attrs
        |> Map.delete(:kaapi_uuid)
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:assistant_id, 1)

      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid? == false
      assert %{kaapi_uuid: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset uses default settings when not provided", %{organization_id: organization_id} do
      attrs =
        @valid_attrs
        |> Map.delete(:settings)
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:assistant_id, 1)

      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :settings) == nil
      assert get_field(changeset, :settings) == %{}
    end

    test "changeset uses default provider when not provided", %{organization_id: organization_id} do
      attrs =
        @valid_attrs
        |> Map.delete(:provider)
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:assistant_id, 1)

      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid?
      assert get_field(changeset, :provider) == "openai"
    end

    test "changeset with optional fields", %{organization_id: organization_id} do
      attrs =
        @valid_attrs
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:assistant_id, 1)
        |> Map.put(:description, "Version 1 of the assistant")
        |> Map.put(:version_number, 1)

      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :description) == "Version 1 of the assistant"
      assert get_change(changeset, :version_number) == 1
    end

    test "changeset with failure_reason when status is failed", %{
      organization_id: organization_id
    } do
      attrs =
        @valid_attrs
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
        @valid_attrs
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:assistant_id, 1)

      changeset =
        AssistantConfigVersion.changeset(
          %AssistantConfigVersion{},
          Map.put(base_attrs, :status, :in_progress)
        )

      assert changeset.valid?
      assert get_field(changeset, :status) == :in_progress

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
  end
end
