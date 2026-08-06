defmodule GlificWeb.Schema.AssistantChatTest do
  @moduledoc """
  GraphQL integration tests for the assistant chat sandbox surface:
  - sendAssistantMessage mutation
  - authorization enforcement
  - cross-org isolation
  """

  use GlificWeb.ConnCase
  use Wormwood.GQLCase
  import Tesla.Mock

  alias Glific.Assistants.Assistant
  alias Glific.Assistants.AssistantConfigVersion
  alias Glific.Partners
  alias Glific.Repo

  load_gql(:send_message, GlificWeb.Schema, "assets/gql/assistant_chat/send_message.gql")

  defp enable_kaapi(%{organization_id: org_id}) do
    {:ok, credential} =
      Partners.create_credential(%{
        organization_id: org_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{"api_key" => "sk_test_key"}
      })

    {:ok, _credential} =
      Partners.update_credential(credential, %{
        keys: %{},
        secrets: %{"api_key" => "sk_test_key"},
        is_active: true,
        organization_id: org_id,
        shortcode: "kaapi"
      })

    :ok
  end

  defp create_live_assistant(organization_id) do
    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{
        name: "Chat Sandbox Assistant #{:rand.uniform(10_000)}",
        organization_id: organization_id,
        kaapi_uuid: "kaapi_uuid_gql"
      })
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        organization_id: organization_id,
        provider: "openai",
        model: "gpt-4o",
        prompt: "You are a helpful assistant",
        settings: %{"temperature" => 1.0},
        status: :ready,
        kaapi_version_number: 1
      })
      |> Repo.insert()

    {:ok, assistant} =
      assistant
      |> Assistant.set_active_config_version_changeset(%{
        active_config_version_id: config_version.id
      })
      |> Repo.update()

    assistant
  end

  defp kaapi_success_mock do
    mock(fn %Tesla.Env{method: :post} ->
      %Tesla.Env{
        status: 200,
        body: %{data: %{job_id: "job_gql_001", conversation: %{id: "conv_gql_001"}}}
      }
    end)
  end

  describe "sendAssistantMessage mutation" do
    setup :enable_kaapi

    test "staff user can dispatch a chat message and receives a job_id",
         %{staff: user, organization_id: organization_id} do
      assistant = create_live_assistant(organization_id)
      kaapi_success_mock()

      result =
        auth_query_gql_by(:send_message, user,
          variables: %{"input" => %{"assistantId" => assistant.id, "message" => "Hello"}}
        )

      assert {:ok, query_data} = result

      response = get_in(query_data, [:data, "sendAssistantMessage"])
      assert response["jobId"] == "job_gql_001"
      assert response["conversationId"] == "conv_gql_001"
      assert response["requestId"] != nil
      assert response["errors"] in [nil, []]
    end

    test "returns an error for an assistant belonging to another organization",
         %{staff: user} do
      other_organization = Glific.Fixtures.organization_fixture()
      assistant = create_live_assistant(other_organization.id)

      result =
        auth_query_gql_by(:send_message, user,
          variables: %{"input" => %{"assistantId" => assistant.id, "message" => "Hello"}}
        )

      assert {:ok, query_data} = result
      assert get_in(query_data, [:errors]) != nil
    end

    test "user with no authorized role is rejected",
         %{staff: user, organization_id: organization_id} do
      assistant = create_live_assistant(organization_id)
      no_role_user = %{user | roles: []}

      result =
        auth_query_gql_by(:send_message, no_role_user,
          variables: %{"input" => %{"assistantId" => assistant.id, "message" => "Hello"}}
        )

      assert {:ok, query_data} = result
      errors = get_in(query_data, [:errors])
      assert errors != nil && length(errors) > 0
    end
  end
end
