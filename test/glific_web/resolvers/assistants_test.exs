defmodule GlificWeb.Resolvers.AssistantsTest do
  @moduledoc """
  Test suite for GraphQL resolvers related to Assistants.
  """
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  import Ecto.Query

  alias Glific.Assistants
  alias Glific.Assistants.Assistant
  alias Glific.Assistants.AssistantConfigVersion
  alias Glific.Partners
  alias Glific.Repo

  load_gql(
    :create_knowledge_base,
    GlificWeb.Schema,
    "assets/gql/assistants/create_knowledge_base.gql"
  )

  load_gql(
    :list_assistant_config_versions,
    GlificWeb.Schema,
    "assets/gql/assistants/list_assistant_config_versions.gql"
  )

  load_gql(
    :assistant_versions,
    GlificWeb.Schema,
    "assets/gql/assistants/assistant_versions.gql"
  )

  load_gql(
    :set_live_version,
    GlificWeb.Schema,
    "assets/gql/assistants/set_live_version.gql"
  )

  describe "create_knowledge_base/3" do
    setup :enable_kaapi

    test "creates and returns knowledge base on success", %{staff: user} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{
              data: %{job_id: "job_abc123"}
            }
          }
      end)

      {:ok, query_data} =
        auth_query_gql_by(:create_knowledge_base, user,
          variables: %{
            "media_info" => [
              %{"file_id" => "file_abc", "filename" => "doc.pdf"},
              %{"file_id" => "file_xyz", "filename" => "notes.txt"}
            ]
          }
        )

      knowledge_base = query_data.data["create_knowledge_base"]["knowledge_base"]
      assert knowledge_base["id"] != nil
      assert knowledge_base["name"] != nil
      assert knowledge_base["knowledge_base_version_id"] != nil
      assert knowledge_base["status"] == "in_progress"
    end

    test "returns knowledge base without creating one", %{
      staff: user,
      organization_id: organization_id
    } do
      {:ok, knowledge_base} =
        Assistants.create_knowledge_base(%{
          name: "Test Knowledge Base",
          organization_id: organization_id
        })

      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{
              data: %{job_id: "job_abc123"}
            }
          }
      end)

      {:ok, query_data} =
        auth_query_gql_by(:create_knowledge_base, user,
          variables: %{
            "id" => knowledge_base.id,
            "media_info" => [
              %{"file_id" => "file_abc", "filename" => "doc.pdf"},
              %{"file_id" => "file_xyz", "filename" => "notes.txt"}
            ]
          }
        )

      response = query_data.data["create_knowledge_base"]["knowledge_base"]

      assert response["id"] == to_string(knowledge_base.id)
      assert response["name"] == knowledge_base.name
      assert response["knowledge_base_version_id"] != nil
      assert response["status"] == "in_progress"
    end

    test "returns error when kaapi api fails", %{staff: user} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 500,
            body: %{error: "Internal server error"}
          }
      end)

      {:ok, query_data} =
        auth_query_gql_by(:create_knowledge_base, user,
          variables: %{
            "media_info" => [
              %{"file_id" => "file_abc", "filename" => "doc.pdf"}
            ]
          }
        )

      assert query_data.data["create_knowledge_base"] == nil
      assert [error | _] = query_data.errors
      assert error[:message] == "Failed to create knowledge base"
    end
  end

  describe "list_assistant_config_versions/3" do
    setup :enable_kaapi

    test "returns all config versions for the organization", %{
      staff: user,
      organization_id: organization_id
    } do
      {:ok, assistant} = create_assistant_with_config_version(organization_id)

      assistant_configuration_version_list =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^assistant.id)
        |> Repo.all()

      assert length(assistant_configuration_version_list) == 3

      {:ok, query_data} = auth_query_gql_by(:list_assistant_config_versions, user)

      versions = query_data.data["assistantConfigVersions"]
      assert length(versions) == 1
      assert hd(versions)["status"] == "ready"
    end
  end

  defp create_assistant_with_config_version(organization_id, kaapi_uuid \\ nil) do
    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{
        name: "Test Assistant #{System.unique_integer()}",
        organization_id: organization_id,
        kaapi_uuid: kaapi_uuid
      })
      |> Repo.insert()

    {:ok, _config_version1} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        prompt: "You are a helpful assistant",
        model: "gpt-4o",
        provider: "openai",
        settings: %{},
        status: :failed,
        organization_id: organization_id
      })
      |> Repo.insert()

    {:ok, _config_version1} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        prompt: "You are a helpful assistant",
        model: "gpt-4o",
        provider: "openai",
        settings: %{},
        status: :in_progress,
        organization_id: organization_id
      })
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        prompt: "You are a helpful assistant",
        model: "gpt-4o",
        provider: "openai",
        settings: %{},
        status: :ready,
        organization_id: organization_id
      })
      |> Repo.insert()

    {:ok, assistant} =
      assistant
      |> Assistant.set_active_config_version_changeset(%{
        active_config_version_id: config_version.id
      })
      |> Repo.update()

    {:ok, assistant}
  end

  load_gql(
    :clone_assistant,
    GlificWeb.Schema,
    "assets/gql/assistants/clone_assistant.gql"
  )

  describe "clone_assistant/3" do
    setup :enable_kaapi

    test "initiates clone for an existing assistant", %{
      staff: user,
      organization_id: organization_id
    } do
      {:ok, assistant} = create_assistant_with_config_version(organization_id, "kaapi_clone_test")

      {:ok, query_data} =
        auth_query_gql_by(:clone_assistant, user, variables: %{"id" => assistant.id})

      result = query_data.data["cloneAssistant"]
      assert result["message"] == "Assistant clone initiated"
      assert result["errors"] == nil
    end

    test "returns error when assistant not found", %{staff: user} do
      {:ok, query_data} =
        auth_query_gql_by(:clone_assistant, user, variables: %{"id" => -1})

      result = query_data.data["cloneAssistant"]
      assert result["message"] == nil
      assert [%{"key" => _, "message" => "Resource not found"}] = result["errors"]
    end
  end

  describe "assistant_versions/3" do
    test "returns all versions for an assistant ordered by version_number desc", %{
      staff: user,
      organization_id: organization_id
    } do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{name: "Test Assistant", organization_id: organization_id})
        |> Repo.insert()

      {:ok, v1} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "Prompt v1",
          settings: %{},
          status: :ready,
          version_number: 1
        })
        |> Repo.insert()

      {:ok, _v2} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "Prompt v2",
          settings: %{},
          status: :in_progress,
          version_number: 2
        })
        |> Repo.insert()

      {:ok, _assistant} =
        assistant
        |> Assistant.set_active_config_version_changeset(%{active_config_version_id: v1.id})
        |> Repo.update()

      {:ok, query_data} =
        auth_query_gql_by(:assistant_versions, user, variables: %{"assistant_id" => assistant.id})

      versions = query_data.data["assistantVersions"]
      assert length(versions) == 2

      # Ordered newest first
      assert hd(versions)["version_number"] == 2
      assert List.last(versions)["version_number"] == 1

      # is_live reflects active_config_version_id
      live_version = Enum.find(versions, & &1["is_live"])
      assert live_version["id"] == to_string(v1.id)
    end

    test "returns empty versions for a non-existent assistant", %{staff: user} do
      {:ok, query_data} =
        auth_query_gql_by(:assistant_versions, user, variables: %{"assistant_id" => 0})

      versions = query_data.data["assistantVersions"]
      # Absinthe returns a list with nil entries or an empty list when the resolver errors
      assert versions == [] or Enum.all?(versions, &is_nil(&1["id"]))
    end
  end

  describe "set_live_version/3" do
    test "updates active_config_version_id when version is ready", %{
      staff: user,
      organization_id: organization_id
    } do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{name: "Live Version Test", organization_id: organization_id})
        |> Repo.insert()

      {:ok, v1} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "Prompt v1",
          settings: %{},
          status: :ready,
          version_number: 1
        })
        |> Repo.insert()

      {:ok, _assistant} =
        assistant
        |> Assistant.set_active_config_version_changeset(%{active_config_version_id: v1.id})
        |> Repo.update()

      {:ok, v2} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "Prompt v2",
          settings: %{},
          status: :ready,
          version_number: 2
        })
        |> Repo.insert()

      {:ok, query_data} =
        auth_query_gql_by(:set_live_version, user,
          variables: %{"assistantId" => assistant.id, "versionId" => v2.id}
        )

      result = query_data.data["setLiveVersion"]["assistant"]
      assert result["activeConfigVersionId"] == to_string(v2.id)
      assert result["liveVersionNumber"] == 2
    end

    test "returns error when version is not in ready status", %{
      staff: user,
      organization_id: organization_id
    } do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Live Version Error Test",
          organization_id: organization_id
        })
        |> Repo.insert()

      {:ok, in_progress_version} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "Draft prompt",
          settings: %{},
          status: :in_progress
        })
        |> Repo.insert()

      {:ok, query_data} =
        auth_query_gql_by(:set_live_version, user,
          variables: %{
            "assistantId" => assistant.id,
            "versionId" => in_progress_version.id
          }
        )

      assert query_data.data["setLiveVersion"] == nil
      assert query_data.errors != nil
    end
  end

  defp enable_kaapi(%{organization_id: organization_id}) do
    Partners.create_credential(%{
      organization_id: organization_id,
      shortcode: "kaapi",
      keys: %{},
      secrets: %{
        "api_key" => "sk_test_key"
      },
      is_active: true
    })

    :ok
  end
end
