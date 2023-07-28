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

  load_gql(:list, GlificWeb.Schema, "assets/gql/contact_groups/list.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/contact_groups/create.gql")
  load_gql(:info, GlificWeb.Schema, "assets/gql/contact_groups/info.gql")

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

  test "update group contacts", %{staff: user_auth} do
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

  test "update contact groups", %{staff: user_auth} do
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

  test "list contact groups", %{staff: user_auth} do
    [contact1, contact2 | _] =
      Contacts.list_contacts(%{filter: %{organization_id: user_auth.organization_id}})

    [group1, group2 | _] =
      Groups.list_groups(%{filter: %{organization_id: user_auth.organization_id}})

    Groups.GroupContacts.update_group_contacts(%{
      organization_id: user_auth.organization_id,
      group_id: group1.id,
      add_contact_ids: [contact1.id, contact2.id],
      delete_contact_ids: []
    })

    Groups.GroupContacts.update_group_contacts(%{
      organization_id: user_auth.organization_id,
      group_id: group2.id,
      add_contact_ids: [contact1.id, contact2.id],
      delete_contact_ids: []
    })

    limit = 4

    ## List contact groups
    result =
      auth_query_gql_by(:list, user_auth,
        variables: %{"opts" => %{"limit" => limit, "offset" => 0}}
      )

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "contactGroups"])) <= limit
    assert length(get_in(query_data, [:data, "contactGroups"])) > 0

    ## List with group id filters
    result =
      auth_query_gql_by(:list, user_auth, variables: %{"filter" => %{"group_id" => group1.id}})

    assert {:ok, query_data} = result

    assert length(get_in(query_data, [:data, "contactGroups"])) ==
             Groups.contacts_count(%{id: group1.id})

    ## List with contact id filters
    contact1 = Repo.preload(contact1, :groups)

    result =
      auth_query_gql_by(:list, user_auth, variables: %{"filter" => %{"contact_id" => contact1.id}})

    assert {:ok, query_data} = result

    assert length(get_in(query_data, [:data, "contactGroups"])) == length(contact1.groups)
  end

  test "create a contact group and test possible scenarios and errors", %{staff: user_auth} do
    label = "Default Group"

    {:ok, group} =
      Repo.fetch_by(Group, %{label: label, organization_id: user_auth.organization_id})

    name = "NGO Main Account"

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

    first_id = contact_group["id"]
    # try creating the same contact group entry twice and ensure we get the same id
    result =
      auth_query_gql_by(:create, user_auth,
        variables: %{"input" => %{"contact_id" => contact.id, "group_id" => group.id}}
      )

    assert {:ok, query_data} = result

    second_id = get_in(query_data, [:data, "createContactGroup", "contact_group", "id"])
    assert first_id == second_id
  end

  test "info on groups 1 and 2 return some data", %{staff: user_auth} do
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

    assert {:ok, _query_data} = result

    {:ok, query_data} = auth_query_gql_by(:info, user, variables: %{"id" => group.id})

    str = get_in(query_data, [:data, "groupInfo"])
    assert is_binary(str)
    json = Jason.decode!(str)
    assert(Enum.count(json) > 0)
    assert(Map.has_key?(json, "total"))
  end
end
