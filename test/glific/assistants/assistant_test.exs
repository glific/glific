defmodule Glific.Assistants.AssistantTest do
  @moduledoc """
  Tests for Assistant schema and changesets
  """
  use Glific.DataCase

  alias Glific.{
    Assistants,
    Assistants.Assistant,
    Partners,
    Repo
  }

  setup %{organization_id: organization_id} do
    enable_kaapi(%{organization_id: organization_id})

    # Create a knowledge base and version for tests
    {:ok, kb} =
      Assistants.create_knowledge_base(%{
        name: "Test KB",
        organization_id: organization_id
      })

    {:ok, kb_version} =
      Assistants.create_knowledge_base_version(%{
        knowledge_base_id: kb.id,
        llm_service_id: "vs_test_123",
        status: :completed,
        organization_id: organization_id,
        files: %{},
        size: 0
      })

    valid_attrs = %{
      name: "Test Assistant",
      description: "A helpful assistant for testing",
      kaapi_uuid: "test-uuid",
      organization_id: organization_id
    }

    %{
      valid_attrs: valid_attrs,
      knowledge_base: kb,
      knowledge_base_version: kb_version
    }
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
          kaapi_uuid: "test-uuid",
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

  describe "create_assistant/1" do
    setup %{organization_id: organization_id, knowledge_base: kb} do
      Tesla.Mock.mock(fn
        %{method: :post, url: _url} ->
          %Tesla.Env{
            status: 200,
            body: %{
              success: true,
              data: %{
                id: "kaapi-uuid-123",
                name: "Test Assistant"
              }
            }
          }
      end)

      %{organization_id: organization_id, knowledge_base: kb}
    end

    test "creates assistant successfully with knowledge base", %{
      organization_id: organization_id,
      knowledge_base: kb
    } do
      params = %{
        name: "Test Assistant",
        description: "A test assistant",
        instructions: "You are helpful",
        temperature: 0.7,
        model: "gpt-4o-mini",
        organization_id: organization_id,
        knowledge_base_id: kb.id
      }

      assert {:ok, result} = Assistants.create_assistant(params)
      assert %{assistant: assistant, config_version: config_version} = result

      # Check assistant
      assert assistant.name == "Test Assistant"
      assert assistant.description == "A test assistant"
      assert assistant.kaapi_uuid == "kaapi-uuid-123"
      assert assistant.organization_id == organization_id
      assert assistant.active_config_version_id == config_version.id

      # Check config version
      assert config_version.assistant_id == assistant.id
      assert config_version.prompt == "You are helpful"
      assert config_version.model == "gpt-4o-mini"
      assert config_version.provider == "kaapi"
      assert config_version.settings.temperature == 0.7
      assert config_version.status == :ready
      assert config_version.organization_id == organization_id
    end

    test "returns error when knowledge_base_id is nil", %{organization_id: organization_id} do
      params = %{
        name: "Test Assistant",
        instructions: "You are helpful",
        organization_id: organization_id,
        knowledge_base_id: nil
      }

      assert {:error, error_message} = Assistants.create_assistant(params)
      assert error_message == "Knowledge base is required for assistant creation"
    end

    test "returns error when knowledge_base_id is missing", %{organization_id: organization_id} do
      params = %{
        name: "Test Assistant",
        instructions: "You are helpful",
        organization_id: organization_id
      }

      assert {:error, error_message} = Assistants.create_assistant(params)
      assert error_message == "Knowledge base is required for assistant creation"
    end

    test "generates temp name when name is nil", %{
      organization_id: organization_id,
      knowledge_base: kb
    } do
      params = %{
        name: nil,
        instructions: "You are helpful",
        organization_id: organization_id,
        knowledge_base_id: kb.id
      }

      assert {:ok, result} = Assistants.create_assistant(params)
      assert %{assistant: assistant} = result

      # Should have generated name like "Assistant-abc123"
      assert assistant.name =~ ~r/^Assistant-[a-f0-9]+$/
    end

    test "uses default values when optional params are missing", %{
      organization_id: organization_id,
      knowledge_base: kb
    } do
      params = %{
        name: "Minimal Assistant",
        organization_id: organization_id,
        knowledge_base_id: kb.id
      }

      assert {:ok, result} = Assistants.create_assistant(params)
      assert %{assistant: assistant, config_version: config_version} = result

      # Check defaults
      assert config_version.prompt == "You are a helpful assistant"
      assert config_version.model == "gpt-4o"
      assert config_version.settings.temperature == 1
      assert config_version.status == :ready
      assert assistant.description == nil
    end

    test "returns error when Kaapi API fails", %{
      organization_id: organization_id,
      knowledge_base: kb
    } do
      Tesla.Mock.mock(fn
        %{method: :post, url: _url} ->
          %Tesla.Env{
            status: 500,
            body: %{
              success: false,
              error: "Internal server error",
              data: nil
            }
          }
      end)

      params = %{
        name: "Failing Assistant",
        instructions: "You are helpful",
        organization_id: organization_id,
        knowledge_base_id: kb.id
      }

      assert {:error, error} = Assistants.create_assistant(params)
      assert is_map(error)
      assert error.status == 500
      assert error.body.error == "Internal server error"
    end

    test "active_config_version_id is set correctly", %{
      organization_id: organization_id,
      knowledge_base: kb
    } do
      params = %{
        name: "Active Config Test",
        organization_id: organization_id,
        knowledge_base_id: kb.id
      }

      assert {:ok, result} = Assistants.create_assistant(params)
      assert %{assistant: assistant, config_version: config_version} = result

      # Reload assistant from DB to verify active_config_version_id was saved
      reloaded_assistant = Repo.get!(Assistant, assistant.id)
      assert reloaded_assistant.active_config_version_id == config_version.id

      # Verify config version belongs to this assistant
      assert config_version.assistant_id == assistant.id
    end

    test "links config version to knowledge base version", %{
      organization_id: organization_id,
      knowledge_base: kb
    } do
      params = %{
        name: "KB Link Test",
        organization_id: organization_id,
        knowledge_base_id: kb.id
      }

      assert {:ok, result} = Assistants.create_assistant(params)
      assert %{config_version: config_version} = result

      # Verify the link was created
      import Ecto.Query

      link =
        from(acvkbv in "assistant_config_version_knowledge_base_versions",
          where: acvkbv.assistant_config_version_id == ^config_version.id,
          select: %{
            assistant_config_version_id: acvkbv.assistant_config_version_id,
            knowledge_base_version_id: acvkbv.knowledge_base_version_id
          }
        )
        |> Repo.one()

      assert link != nil
      assert link.assistant_config_version_id == config_version.id
    end

    test "returns error when knowledge base has no versions", %{
      organization_id: organization_id
    } do
      params = %{
        name: "Test Assistant",
        organization_id: organization_id
      }

      assert {:error, error_message} = Assistants.create_assistant(params)
      assert error_message == "Knowledge base is required for assistant creation"
    end
  end

  defp enable_kaapi(attrs) do
    {:ok, credential} =
      Partners.create_credential(%{
        organization_id: attrs.organization_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{
          "api_key" => "sk_3fa22108-f464-41e5-81d9-d8a298854430"
        }
      })

    valid_update_attrs = %{
      keys: %{},
      secrets: %{
        "api_key" => "sk_3fa22108-f464-41e5-81d9-d8a298854430"
      },
      is_active: true,
      organization_id: attrs.organization_id,
      shortcode: "kaapi"
    }

    Partners.update_credential(credential, valid_update_attrs)
  end
end
