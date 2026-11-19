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

  alias Glific.Fixtures

  load_gql(:send_message, GlificWeb.Schema, "assets/gql/assistant_chat/send_message.gql")

  defp enable_kaapi(%{organization_id: organization_id}) do
    Fixtures.kaapi_credential_fixture(%{organization_id: organization_id})
    :ok
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
      assistant = Fixtures.live_assistant_fixture(%{organization_id: organization_id})
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

    test "dispatches the selected config version when configVersionId is given",
         %{staff: user, organization_id: organization_id} do
      assistant = Fixtures.live_assistant_fixture(%{organization_id: organization_id})

      selected_version =
        Fixtures.assistant_config_version_fixture(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          kaapi_version_number: 5
        })

      mock(fn %Tesla.Env{method: :post, body: body} ->
        assert Jason.decode!(body)["config"]["version"] == 5

        %Tesla.Env{
          status: 200,
          body: %{data: %{job_id: "job_gql_002", conversation: %{id: "conv_gql_002"}}}
        }
      end)

      result =
        auth_query_gql_by(:send_message, user,
          variables: %{
            "input" => %{
              "assistantId" => assistant.id,
              "message" => "Hello",
              "configVersionId" => selected_version.id
            }
          }
        )

      assert {:ok, query_data} = result
      assert get_in(query_data, [:data, "sendAssistantMessage", "jobId"]) == "job_gql_002"
    end

    test "returns an error for an assistant belonging to another organization",
         %{staff: user} do
      other_organization = Fixtures.organization_fixture()
      assistant = Fixtures.live_assistant_fixture(%{organization_id: other_organization.id})

      result =
        auth_query_gql_by(:send_message, user,
          variables: %{"input" => %{"assistantId" => assistant.id, "message" => "Hello"}}
        )

      assert {:ok, query_data} = result
      assert get_in(query_data, [:errors]) != nil
    end

    test "user with no authorized role is rejected",
         %{staff: user, organization_id: organization_id} do
      assistant = Fixtures.live_assistant_fixture(%{organization_id: organization_id})
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
