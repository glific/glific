defmodule GlificWeb.Schema.ContactGroupTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Fixtures,
    Groups.Group,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    Fixtures.group_fixture()
    :ok
  end

  load_gql(:create, GlificWeb.Schema, "assets/gql/contact_groups/create.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/contact_groups/delete.gql")

  load_gql(
    :update_group_contacts,
    GlificWeb.Schema,
    "assets/gql/contact_groups/update_group_contacts.gql"
  )

  test "update group contacts" do
    label = "Default Group"
    {:ok, group} = Repo.fetch_by(Group, %{label: label})

    [contact1, contact2 | _] = Contacts.list_contacts()

    # add group contacts
    result =
      query_gql_by(:update_group_contacts,
        variables: %{
          "input" => %{
            "group_id" => group.id,
            "add_contact_ids" => [contact1.id, contact2.id],
            "delete_contact_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    group_contacts = get_in(query_data, [:data, "updateGroupContacts", "groupContacts"])
    assert length(group_contacts) == 2

    # delete group contacts
    result =
      query_gql_by(:update_group_contacts,
        variables: %{
          "input" => %{
            "group_id" => group.id,
            "add_contact_ids" => [],
            "delete_contact_ids" => [contact1.id]
          }
        }
      )

    assert {:ok, query_data} = result
    number_deleted = get_in(query_data, [:data, "updateGroupContacts", "numberDeleted"])
    assert number_deleted == 1

    # test for incorrect contact id
    result =
      query_gql_by(:update_group_contacts,
        variables: %{
          "input" => %{
            "group_id" => group.id,
            "add_contact_ids" => ["-1"],
            "delete_contact_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    group_contacts = get_in(query_data, [:data, "updateGroupContacts", "groupContacts"])
    assert group_contacts == []
  end

  test "create a contact group and test possible scenarios and errors" do
    label = "Default Group"
    {:ok, group} = Repo.fetch_by(Group, %{label: label})
    name = "Glific Admin"
    {:ok, contact} = Repo.fetch_by(Contact, %{name: name})

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"contact_id" => contact.id, "group_id" => group.id}}
      )

    assert {:ok, query_data} = result

    contact_group = get_in(query_data, [:data, "createContactGroup", "contact_group"])

    assert contact_group["contact"]["id"] |> String.to_integer() == contact.id
    assert contact_group["group"]["id"] |> String.to_integer() == group.id

    # try creating the same contact group entry twice
    result =
      query_gql_by(:create,
        variables: %{"input" => %{"contact_id" => contact.id, "group_id" => group.id}}
      )

    assert {:ok, query_data} = result

    contact = get_in(query_data, [:data, "createContactGroup", "errors", Access.at(0), "message"])
    assert contact == "has already been taken"
  end

  test "delete a contact group" do
    label = "Default Group"
    {:ok, group} = Repo.fetch_by(Group, %{label: label})
    name = "Glific Admin"
    {:ok, contact} = Repo.fetch_by(Contact, %{name: name})

    {:ok, query_data} =
      query_gql_by(:create,
        variables: %{"input" => %{"contact_id" => contact.id, "group_id" => group.id}}
      )

    contact_group_id = get_in(query_data, [:data, "createContactGroup", "contact_group", "id"])

    result = query_gql_by(:delete, variables: %{"id" => contact_group_id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "deleteContactGroup", "errors"]) == nil

    # try to delete incorrect entry
    result = query_gql_by(:delete, variables: %{"id" => contact_group_id})
    assert {:ok, query_data} = result

    contact = get_in(query_data, [:data, "deleteContactGroup", "errors", Access.at(0), "message"])
    assert contact == "Resource not found"
  end
end
