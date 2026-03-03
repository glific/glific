defmodule GlificWeb.Resolvers.AssistantsTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.Assistants
  alias Glific.Partners

  load_gql(
    :create_knowledge_base,
    GlificWeb.Schema,
    "assets/gql/assistants/create_knowledge_base.gql"
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
      assert knowledge_base["vector_store_id"] != nil
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
      assert response["vector_store_id"] != nil
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
