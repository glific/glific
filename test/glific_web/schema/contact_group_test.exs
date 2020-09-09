defmodule GlificWeb.Schema.ContactGroupTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Fixtures,
    Groups,
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

  load_gql(
    :update_contact_groups,
    GlificWeb.Schema,
    "assets/gql/contact_groups/update_contact_groups.gql"
  )

  test "update group contacts", %{manager: user_auth} do
    user = Fixtures.user_fixture()
    label = "Default Group"

    {:ok, group} =
      Repo.fetch_by(Group, %{label: label, organization_id: user_auth.organization_id})

    [contact1, contact2 | _] =
      Contacts.list_contacts(%{filter: %{organization_id: user.organization_id}})

    # add group contacts
    result =
      auth_query_gql_by(:update_group_contacts, user_auth,
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
      auth_query_gql_by(:update_group_contacts, user_auth,
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
      auth_query_gql_by(:update_group_contacts, user_auth,
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

  test "update contact groups", %{manager: user_auth} do
    name = "Default receiver"

    {:ok, contact} =
      Repo.fetch_by(Contact, %{name: name, organization_id: user_auth.organization_id})

    user = Fixtures.user_fixture()
    [group1, group2 | _] = Groups.list_groups(%{filter: %{organization_id: user.organization_id}})

    # add contact groups
    result =
      auth_query_gql_by(:update_contact_groups, user_auth,
        variables: %{
          "input" => %{
            "contact_id" => contact.id,
            "add_group_ids" => [group1.id, group2.id],
            "delete_group_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    contact_groups = get_in(query_data, [:data, "updateContactGroups", "contactGroups"])
    assert length(contact_groups) == 2

    # delete contact groups
    result =
      auth_query_gql_by(:update_contact_groups, user_auth,
        variables: %{
          "input" => %{
            "contact_id" => contact.id,
            "add_group_ids" => [],
            "delete_group_ids" => [group1.id]
          }
        }
      )

    assert {:ok, query_data} = result
    number_deleted = get_in(query_data, [:data, "updateContactGroups", "numberDeleted"])
    assert number_deleted == 1

    # test for incorrect group id
    result =
      auth_query_gql_by(:update_contact_groups, user_auth,
        variables: %{
          "input" => %{
            "contact_id" => contact.id,
            "add_group_ids" => ["-1"],
            "delete_group_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    contact_groups = get_in(query_data, [:data, "updateContactGroups", "contactGroups"])
    assert contact_groups == []
  end

  test "create a contact group and test possible scenarios and errors", %{manager: user_auth} do
    label = "Default Group"

    {:ok, group} =
      Repo.fetch_by(Group, %{label: label, organization_id: user_auth.organization_id})

    name = "Glific Admin"

    {:ok, contact} =
      Repo.fetch_by(Contact, %{name: name, organization_id: user_auth.organization_id})

    result =
      auth_query_gql_by(:create, user_auth,
        variables: %{"input" => %{"contact_id" => contact.id, "group_id" => group.id}}
      )

    assert {:ok, query_data} = result

    contact_group = get_in(query_data, [:data, "createContactGroup", "contact_group"])

    assert contact_group["contact"]["id"] |> String.to_integer() == contact.id
    assert contact_group["group"]["id"] |> String.to_integer() == group.id

    # try creating the same contact group entry twice
    result =
      auth_query_gql_by(:create, user_auth,
        variables: %{"input" => %{"contact_id" => contact.id, "group_id" => group.id}}
      )

    assert {:ok, query_data} = result

    contact = get_in(query_data, [:data, "createContactGroup", "errors", Access.at(0), "message"])
    assert contact == "has already been taken"
  end

  test "delete a contact group", %{manager: user_auth} do
    label = "Default Group"

    {:ok, group} =
      Repo.fetch_by(Group, %{label: label, organization_id: user_auth.organization_id})

    name = "Glific Admin"

    {:ok, contact} =
      Repo.fetch_by(Contact, %{name: name, organization_id: user_auth.organization_id})

    {:ok, query_data} =
      auth_query_gql_by(:create, user_auth,
        variables: %{"input" => %{"contact_id" => contact.id, "group_id" => group.id}}
      )

    contact_group_id = get_in(query_data, [:data, "createContactGroup", "contact_group", "id"])

    result = auth_query_gql_by(:delete, user_auth, variables: %{"id" => contact_group_id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "deleteContactGroup", "errors"]) == nil

    # try to delete incorrect entry
    result = auth_query_gql_by(:delete, user_auth, variables: %{"id" => contact_group_id})
    assert {:ok, query_data} = result

    contact = get_in(query_data, [:data, "deleteContactGroup", "errors", Access.at(0), "message"])
    assert contact == "Resource not found"
  end
end
