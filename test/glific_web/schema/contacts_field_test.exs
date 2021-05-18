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

  test "contact fields returns list of contact fields", %{staff: user} = attrs do
    _contacts_field_2 =
      Fixtures.contacts_field_fixture(%{
        organization_id: attrs.organization_id
      })

    _contacts_field_2 =
      Fixtures.contacts_field_fixture(%{
        organization_id: attrs.organization_id,
        name: "Nationality",
        shortcode: "nationality"
      })

    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "ASC"}})
    assert {:ok, query_data} = result
    # consulting_hours = get_in(query_data, [:data, "consultingHours"])
    # assert length(consulting_hours) > 0
    # [consulting_hour | _] = consulting_hours
    # assert get_in(consulting_hour, ["staff"]) == "Jon Cavin"

    # result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"isBillable" => false}})
    # assert {:ok, query_data} = result
    # consulting_hours = get_in(query_data, [:data, "consultingHours"])
    # assert length(consulting_hours) > 0
    # [consulting_hour | _] = consulting_hours
    # assert get_in(consulting_hour, ["staff"]) == "Ken Cavin"

    # result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"participants" => "John"}})
    # assert {:ok, query_data} = result
    # consulting_hours = get_in(query_data, [:data, "consultingHours"])
    # assert length(consulting_hours) > 0
    # [consulting_hour | _] = consulting_hours
    # assert get_in(consulting_hour, ["participants"]) == "John Doe"

    # result =
    #   auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})

    # assert {:ok, query_data} = result
    # consulting_hours = get_in(query_data, [:data, "consultingHours"])
    # assert length(consulting_hours) == 1
  end

  # test "update a contact fields", %{manager: user} = attrs do
  #   consulting_hour = Fixtures.contacts_field_fixture(%{organization_id: attrs.organization_id})

  #   result =
  #     auth_query_gql_by(:update, user,
  #       variables: %{
  #         "id" => consulting_hour.id,
  #         "input" => %{"duration" => 20}
  #       }
  #     )

  #   assert {:ok, query_data} = result

  #   duration = get_in(query_data, [:data, "updateConsultingHour", "consultingHour", "duration"])
  #   assert duration == 20
  # end

  # test "delete a contact fields", %{user: user} = attrs do
  #   consulting_hour = Fixtures.contacts_field_fixture(%{organization_id: attrs.organization_id})

  #   result =
  #     auth_query_gql_by(:delete, user,
  #       variables: %{
  #         "id" => consulting_hour.id
  #       }
  #     )

  #   assert {:ok, query_data} = result
  #   content = get_in(query_data, [:data, "deleteConsultingHour", "consultingHour", "content"])
  #   assert content == consulting_hour.content
  # end

  # test "get contact fields and test possible scenarios and errors", %{user: user} = attrs do
  #   consulting_hour = Fixtures.contacts_field_fixture(%{organization_id: attrs.organization_id})

  #   result =
  #     auth_query_gql_by(:by_id, user,
  #       variables: %{
  #         "id" => consulting_hour.id
  #       }
  #     )

  #   assert {:ok, query_data} = result
  #   consulting_hours = get_in(query_data, [:data, "consultingHour", "consultingHour"])

  #   assert consulting_hours["participants"] == consulting_hour.participants
  #   assert consulting_hours["content"] == consulting_hour.content
  #   assert consulting_hours["staff"] == consulting_hour.staff

  #   # testing error message when id is incorrect
  #   result =
  #     auth_query_gql_by(:by_id, user,
  #       variables: %{
  #         "id" => consulting_hour.id + 1
  #       }
  #     )

  #   assert {:ok, query_data} = result
  #   [error] = get_in(query_data, [:errors])
  #   assert error.message == "No consulting hour found with inputted params"
  # end
end
