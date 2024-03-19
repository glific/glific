defmodule GlificWeb.Schema.ContactWaGroupTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Contacts,
    Fixtures,
    Groups.ContactWAGroups,
    Partners,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    organization = SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()

    Partners.create_credential(%{
      organization_id: organization.id,
      shortcode: "maytapi",
      keys: %{},
      secrets: %{
        "product_id" => "3fa22108-f464-41e5-81d9-d8a298854430",
        "token" => "f4f38e00-3a50-4892-99ce-a282fe24d041"
      },
      is_active: true
    })

    :ok
  end

  load_gql(:create, GlificWeb.Schema, "assets/gql/contact_wa_groups/create.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/contact_wa_groups/list.gql")
  load_gql(:sync, GlificWeb.Schema, "assets/gql/contact_wa_groups/sync.gql")
  load_gql(:count, GlificWeb.Schema, "assets/gql/contact_wa_groups/count_wa_contacts.gql")

  load_gql(
    :update_wa_group,
    GlificWeb.Schema,
    "assets/gql/contact_wa_groups/update_wa_group.gql"
  )

  test "create wa group contacts", %{user: user} do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: user.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    contact = Fixtures.contact_fixture(%{organization_id: user.organization_id})

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "wa_group_id" => wa_group.id,
            "contact_id" => contact.id
          }
        }
      )

    assert {:ok, query_data} = result
    wa_group_contacts = get_in(query_data, [:data, "createContactWaGroup", "contactWaGroup"])
    assert wa_group_contacts["contact"]["id"] |> String.to_integer() == contact.id
    assert wa_group_contacts["waGroup"]["id"] |> String.to_integer() == wa_group.id
    assert wa_group_contacts["waGroup"]["label"] == wa_group.label
  end

  test "update wa group contacts", %{user: user} do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: user.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    [contact1, contact2 | _] =
      Contacts.list_contacts(%{filter: %{organization_id: user.organization_id}})

    # add group contacts
    result =
      auth_query_gql_by(:update_wa_group, user,
        variables: %{
          "input" => %{
            "wa_group_id" => wa_group.id,
            "add_wa_contact_ids" => [contact1.id, contact2.id],
            "delete_wa_contact_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    wa_group_contacts = get_in(query_data, [:data, "updateContactWaGroups", "waGroupContacts"])
    assert length(wa_group_contacts) == 2

    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            success: true
          }
        }
    end)

    # delete wa group contacts
    result =
      auth_query_gql_by(:update_wa_group, user,
        variables: %{
          "input" => %{
            "wa_group_id" => wa_group.id,
            "add_wa_contact_ids" => [],
            "delete_wa_contact_ids" => [contact1.id, contact2.id]
          }
        }
      )

    assert {:ok, query_data} = result
    number_deleted = get_in(query_data, [:data, "updateContactWaGroups", "numberDeleted"])
    assert number_deleted == 2

    # test for incorrect contact id
    result =
      auth_query_gql_by(:update_wa_group, user,
        variables: %{
          "input" => %{
            "wa_group_id" => wa_group.id,
            "add_wa_contact_ids" => ["-1"],
            "delete_wa_contact_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    wa_group_contacts = get_in(query_data, [:data, "updateContactWaGroups", "waGroupContacts"])
    assert wa_group_contacts == []
  end

  test "list wa contact groups", %{staff: user} do
    [contact1, contact2 | _] =
      Contacts.list_contacts(%{filter: %{organization_id: user.organization_id}})

    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: user.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    ContactWAGroups.update_contact_wa_groups(%{
      organization_id: user.organization_id,
      wa_group_id: wa_group.id,
      add_wa_contact_ids: [contact1.id, contact2.id],
      delete_wa_contact_ids: []
    })

    limit = 4

    ## List contact whatsapp groups
    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => limit, "offset" => 0}})

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "listContactWaGroup"])) <= limit
    assert length(get_in(query_data, [:data, "listContactWaGroup"])) > 0

    # get the contacts using wa_group id
    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{
            "waGroupId" => wa_group.id
          }
        }
      )

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "listContactWaGroup"])) == 2
  end

  test "sync contacts in wa groups", %{staff: user} do
    result = auth_query_gql_by(:sync, user)
    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "syncWaGroupContacts", "message"])
    assert message == "successfully synced"
  end

  test "delete_wa_group_contacts_by_ids/2 successfully", %{staff: user} do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

    contact_wa_group =
      Fixtures.contact_wa_group_fixture(%{
        organization_id: user.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    deleted_contacts =
      ContactWAGroups.delete_wa_group_contacts_by_ids(
        contact_wa_group.wa_group_id,
        [contact_wa_group.contact_id]
      )

    assert deleted_contacts == {1, nil}
  end

  test "count the contacts associated with wa_groups", %{staff: user} do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

    contact_wa_group =
      Fixtures.contact_wa_group_fixture(%{
        organization_id: user.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    result =
      auth_query_gql_by(:count, user,
        variables: %{
          "filter" => %{
            "waGroupId" => contact_wa_group.wa_group_id
          }
        }
      )

    assert {:ok, query_data} = result
    count = get_in(query_data, [:data, "countContactWaGroup"])
    assert count == 1
  end
end
