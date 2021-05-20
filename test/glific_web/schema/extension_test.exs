defmodule GlificWeb.Schema.ExtensionTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  # alias Glific.Fixtures

  load_gql(:by_id, GlificWeb.Schema, "assets/gql/extension/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/extension/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/extension/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/extension/delete.gql")

  test "create a new extension", %{manager: user} do
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "clientId" => 1,
            "code" => "defmodule URI, do: def default_port(), do: %{phone: 9876543210}",
            "isActive" => true,
            "module" => "URI",
            "name" => "URI"
          }
        }
      )

    assert {:ok, query_data} = result
    extension = get_in(query_data, [:data, "createExtension", "extension"])
    assert extension["code"] == "defmodule URI, do: def default_port(), do: %{phone: 9876543210}"
    assert extension["isActive"] == true
    assert extension["isValid"] == true
    assert extension["name"] == "URI"
  end

  # test "update a consulting hours", %{manager: user} = attrs do
  #   extension = Fixtures.extension_fixture(%{organization_id: attrs.organization_id})

  #   result =
  #     auth_query_gql_by(:update, user,
  #       variables: %{
  #         "id" => extension.id,
  #         "input" => %{"duration" => 20}
  #       }
  #     )

  #   assert {:ok, query_data} = result

  #   duration = get_in(query_data, [:data, "updateConsultingHour", "consultingHour", "duration"])
  #   assert duration == 20
  # end

  # test "delete a consulting hours", %{user: user} = attrs do
  #   extension = Fixtures.extension_fixture(%{organization_id: attrs.organization_id})

  #   result =
  #     auth_query_gql_by(:delete, user,
  #       variables: %{
  #         "id" => extension.id
  #       }
  #     )

  #   assert {:ok, query_data} = result
  #   content = get_in(query_data, [:data, "deleteConsultingHour", "consultingHour", "content"])
  #   assert content == extension.content
  # end

  # test "get consulting hours and test possible scenarios and errors", %{user: user} = attrs do
  #   extension = Fixtures.extension_fixture(%{organization_id: attrs.organization_id})

  #   result =
  #     auth_query_gql_by(:by_id, user,
  #       variables: %{
  #         "id" => extension.id
  #       }
  #     )

  #   assert {:ok, query_data} = result
  #   extensions = get_in(query_data, [:data, "consultingHour", "consultingHour"])

  #   assert extensions["participants"] == extension.participants
  #   assert extensions["content"] == extension.content
  #   assert extensions["staff"] == extension.staff

  #   # testing error message when id is incorrect
  #   result =
  #     auth_query_gql_by(:by_id, user,
  #       variables: %{
  #         "id" => extension.id + 1
  #       }
  #     )

  #   assert {:ok, query_data} = result
  #   [error] = get_in(query_data, [:errors])
  #   assert error.message == "No consulting hour found with inputted params"
  # end
end
