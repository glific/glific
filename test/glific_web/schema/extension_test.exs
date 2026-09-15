defmodule GlificWeb.Schema.ExtensionTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.Fixtures

  load_gql(:by_id, GlificWeb.Schema, "assets/gql/extension/by_id.gql")
  load_gql(:by_client_id, GlificWeb.Schema, "assets/gql/extension/by_client_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/extension/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/extension/update.gql")

  load_gql(
    :get_organization_extension,
    GlificWeb.Schema,
    "assets/gql/extension/update_org_extension.gql"
  )

  load_gql(:delete, GlificWeb.Schema, "assets/gql/extension/delete.gql")

  @code """
  defmodule Extension.Schema.Test.Phone do
    def default_phone() do
      %{phone: 9876543210}
    end
  end
  """

  test "create a new extension", %{glific_admin: user} = attrs do
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "clientId" => attrs.organization_id,
            "code" => @code,
            "isActive" => true,
            "name" => "Extension.Schema.Test.Phone"
          }
        }
      )

    assert {:ok, query_data} = result
    extension = get_in(query_data, [:data, "createExtension", "extension"])

    assert extension["code"] == @code

    assert extension["isActive"] == true
    assert extension["isValid"] == true
    assert extension["name"] == "Extension.Schema.Test.Phone"

    # try creating the same extension twice
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "clientId" => attrs.organization_id,
            "code" => @code,
            "isActive" => true,
            "name" => "Extension.Schema.Test.Phone"
          }
        }
      )

    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "createExtension", "errors", Access.at(0), "message"])
    assert message =~ "has already been taken"
  end

  test "update an extension", %{glific_admin: user} = attrs do
    extension = Fixtures.extension_fixture(%{organization_id: attrs.organization_id})

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => extension.id,
          "input" => %{
            "clientId" => attrs.organization_id,
            "isActive" => true,
            "code" => @code
          }
        }
      )

    assert {:ok, query_data} = result
    extensions = get_in(query_data, [:data, "updateExtension", "extension"])
    assert extensions["isActive"] == true
    assert extensions["isValid"] == true
    assert extensions["name"] == "Test extension"
  end

  test "update an extension by organization id", %{glific_admin: user} = attrs do
    Fixtures.extension_fixture(%{organization_id: attrs.organization_id})

    result =
      auth_query_gql_by(:get_organization_extension, user,
        variables: %{
          "clientId" => attrs.organization_id,
          "input" => %{
            "clientId" => attrs.organization_id,
            "isActive" => true,
            "code" => @code
          }
        }
      )

    assert {:ok, query_data} = result

    extensions = get_in(query_data, [:data, "updateOrganizationExtension", "extension"])

    assert extensions["isActive"] == true
    assert extensions["isValid"] == true
    assert extensions["name"] == "Test extension"
  end

  test "delete an extension", %{glific_admin: user} = attrs do
    extension = Fixtures.extension_fixture(%{organization_id: attrs.organization_id})

    result =
      auth_query_gql_by(:delete, user,
        variables: %{
          "id" => extension.id
        }
      )

    assert {:ok, query_data} = result
    extensions = get_in(query_data, [:data, "deleteExtension", "extension"])
    assert extensions["module"] == "Elixir.Glific.Test.ExtensionFixture"

    error = get_in(query_data, [:data, "deleteExtension", "extension", "errors"])
    assert true == is_nil(error)
  end

  test "get extension and test possible scenarios and errors", %{glific_admin: user} = attrs do
    extension = Fixtures.extension_fixture(%{organization_id: attrs.organization_id})

    result =
      auth_query_gql_by(:by_id, user,
        variables: %{
          "id" => extension.id
        }
      )

    assert {:ok, query_data} = result
    extensions = get_in(query_data, [:data, "extension", "extension"])

    assert extensions["isValid"] == true
    assert extensions["isActive"] == true
    assert extensions["name"] == "Test extension"

    # testing error message when id is incorrect
    result =
      auth_query_gql_by(:by_id, user,
        variables: %{
          "id" => extension.id + 1
        }
      )

    assert {:ok, query_data} = result
    [error] = get_in(query_data, [:data, "extension", "errors"])
    assert error["message"] == "Resource not found"
  end

  test "get extension by client_id and test possible scenarios and errors",
       %{glific_admin: user} = attrs do
    Fixtures.extension_fixture(%{organization_id: attrs.organization_id})

    result =
      auth_query_gql_by(:by_client_id, user,
        variables: %{
          "clientId" => attrs.organization_id
        }
      )

    assert {:ok, query_data} = result
    extensions = get_in(query_data, [:data, "get_organization_extension", "extension"])

    assert extensions["isValid"] == true
    assert extensions["isActive"] == true
    assert extensions["name"] == "Test extension"
  end

  describe "authorization boundary for extensions raised to glific_admin" do
    test "extension queries and mutations reject admin, manager, and staff, but allow glific_admin",
         %{
           user: admin_user,
           manager: manager_user,
           staff: staff_user,
           glific_admin: glific_admin_user
         } = attrs do
      extension = Fixtures.extension_fixture(%{organization_id: attrs.organization_id})

      for rejected_user <- [admin_user, manager_user, staff_user] do
        {:ok, query_data} =
          auth_query_gql_by(:by_id, rejected_user, variables: %{"id" => extension.id})

        [error] = get_in(query_data, [:errors])
        assert error.message == "Unauthorized"

        {:ok, query_data} =
          auth_query_gql_by(:by_client_id, rejected_user,
            variables: %{"clientId" => attrs.organization_id}
          )

        [error] = get_in(query_data, [:errors])
        assert error.message == "Unauthorized"

        {:ok, query_data} =
          auth_query_gql_by(:create, rejected_user,
            variables: %{
              "input" => %{
                "clientId" => attrs.organization_id,
                "code" => @code,
                "isActive" => true,
                "name" => "Rejected create attempt"
              }
            }
          )

        [error] = get_in(query_data, [:errors])
        assert error.message == "Unauthorized"

        {:ok, query_data} =
          auth_query_gql_by(:update, rejected_user,
            variables: %{
              "id" => extension.id,
              "input" => %{
                "clientId" => attrs.organization_id,
                "isActive" => true,
                "code" => @code
              }
            }
          )

        [error] = get_in(query_data, [:errors])
        assert error.message == "Unauthorized"

        {:ok, query_data} =
          auth_query_gql_by(:get_organization_extension, rejected_user,
            variables: %{
              "clientId" => attrs.organization_id,
              "input" => %{
                "clientId" => attrs.organization_id,
                "isActive" => true,
                "code" => @code
              }
            }
          )

        [error] = get_in(query_data, [:errors])
        assert error.message == "Unauthorized"

        {:ok, query_data} =
          auth_query_gql_by(:delete, rejected_user, variables: %{"id" => extension.id})

        [error] = get_in(query_data, [:errors])
        assert error.message == "Unauthorized"
      end

      # gate cleared for glific_admin — no rejected attempt above mutated the fixture
      {:ok, query_data} =
        auth_query_gql_by(:by_id, glific_admin_user, variables: %{"id" => extension.id})

      assert get_in(query_data, [:errors]) == nil

      fetched_extension = get_in(query_data, [:data, "extension", "extension"])
      assert fetched_extension["id"] == to_string(extension.id)

      {:ok, query_data} =
        auth_query_gql_by(:get_organization_extension, glific_admin_user,
          variables: %{
            "clientId" => attrs.organization_id,
            "input" => %{
              "clientId" => attrs.organization_id,
              "isActive" => false,
              "code" => @code
            }
          }
        )

      assert get_in(query_data, [:errors]) == nil

      updated_extension =
        get_in(query_data, [:data, "updateOrganizationExtension", "extension"])

      assert updated_extension["isActive"] == false
    end
  end
end
