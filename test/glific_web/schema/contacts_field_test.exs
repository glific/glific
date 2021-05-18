defmodule GlificWeb.Schema.ContactsFieldTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.Fixtures

  load_gql(:by_id, GlificWeb.Schema, "assets/gql/contacts_field/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/contacts_field/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/contacts_field/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/contacts_field/delete.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/contacts_field/list.gql")
  load_gql(:count, GlificWeb.Schema, "assets/gql/contacts_field/count.gql")

  test "create a contact field", %{manager: user} do
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "name" => "Age",
            "shortcode" => "age"
          }
        }
      )

    assert {:ok, query_data} = result
    contacts_field = get_in(query_data, [:data, "createContactsField", "contactsField"])
    assert contacts_field["name"] == "Age"
    assert contacts_field["shortcode"] == "age"
    assert contacts_field["organization"]["name"] == "Glific"
  end

  test "count returns the number of contact fields", %{staff: user} = attrs do
    {:ok, query_data} = auth_query_gql_by(:count, user)
    inital_count = get_in(query_data, [:data, "countContactsFields"])

    _contacts_field_1 =
      Fixtures.contacts_field_fixture(%{
        organization_id: attrs.organization_id,
        name: "Nationality",
        shortcode: "nationality"
      })

    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countContactsFields"]) > inital_count

    # in case of no results it should return 0
    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"name" => "school"}})

    assert get_in(query_data, [:data, "countContactsFields"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"name" => "Nationality"}})

    assert get_in(query_data, [:data, "countContactsFields"]) == 1
  end

  test "contact fields returns list of contact fields", %{staff: user} = _attrs do
    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "ASC"}})
    assert {:ok, query_data} = result
    contacts_fields = get_in(query_data, [:data, "contactsFields"])
    assert length(contacts_fields) > 0
    [contacts_field | _] = contacts_fields
    assert get_in(contacts_field, ["name"]) == "Name"

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"name" => "Name"}})
    assert {:ok, query_data} = result
    contacts_fields = get_in(query_data, [:data, "contactsFields"])
    assert length(contacts_fields) > 0
    [contacts_field | _] = contacts_fields
    assert get_in(contacts_field, ["name"]) == "Name"

    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})

    assert {:ok, query_data} = result
    contacts_fields = get_in(query_data, [:data, "contactsFields"])
    assert length(contacts_fields) == 1
  end

  test "update a contact fields", %{manager: user} = attrs do
    contacts_field = Fixtures.contacts_field_fixture(%{organization_id: attrs.organization_id})

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => contacts_field.id,
          "input" => %{"name" => "Age category"}
        }
      )

    assert {:ok, query_data} = result

    name = get_in(query_data, [:data, "updateContactsField", "contactsField", "name"])
    assert name == "Age category"
  end

  test "delete a contact fields", %{user: user} = attrs do
    contacts_field = Fixtures.contacts_field_fixture(%{organization_id: attrs.organization_id})

    result =
      auth_query_gql_by(:delete, user,
        variables: %{
          "id" => contacts_field.id
        }
      )

    assert {:ok, query_data} = result
    error = get_in(query_data, [:data, "deleteContactsField", "errors"])
    assert true == is_nil(error)
  end

  test "get contact fields and test possible scenarios and errors", %{user: user} = attrs do
    contacts_field = Fixtures.contacts_field_fixture(%{organization_id: attrs.organization_id})

    result =
      auth_query_gql_by(:by_id, user,
        variables: %{
          "id" => contacts_field.id
        }
      )

    assert {:ok, query_data} = result
    contacts_fields = get_in(query_data, [:data, "contactsField", "contactsField"])

    assert contacts_fields["name"] == contacts_field.name
    assert contacts_fields["shortcode"] == contacts_field.shortcode

    # testing error message when id is incorrect
    result =
      auth_query_gql_by(:by_id, user,
        variables: %{
          "id" => contacts_field.id + 1
        }
      )

    assert {:ok, query_data} = result
    [error] = get_in(query_data, [:data, "contactsField", "errors"])
    assert error["message"] == "Resource not found"
  end
end
