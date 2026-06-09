defmodule GlificWeb.Schema.ContactWaGroupTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Contacts,
    Fixtures,
    Groups.ContactWAGroups,
    Groups.WAGroups,
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

  load_gql(
    :set_primary_phone,
    GlificWeb.Schema,
    "assets/gql/contact_wa_groups/set_primary_phone.gql"
  )

  load_gql(
    :wa_group_with_phones,
    GlificWeb.Schema,
    "assets/gql/wa_groups/with_phones.gql"
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

  test "update WA group", %{staff: user} do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: user.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    # Define params with a different label
    params = %{
      label: "New Group Label",
      organization_id: user.organization_id,
      bsp_id: wa_group.bsp_id,
      wa_managed_phone_id: wa_managed_phone.id
    }

    {:ok, updated_group} = WAGroups.maybe_create_group(params)

    assert updated_group.id == wa_group.id
    assert updated_group.label == "New Group Label"
    assert updated_group.bsp_id == wa_group.bsp_id
  end

  describe "primaryPhone / phones / setPrimaryPhone" do
    setup %{user: user} do
      first_phone =
        Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

      {:ok, first_phone} =
        first_phone
        |> Glific.WAGroup.WAManagedPhone.changeset(%{status: "active"})
        |> Glific.Repo.update()

      {:ok, second_contact} =
        Contacts.maybe_create_contact(%{
          phone: "919999900042",
          organization_id: user.organization_id,
          contact_type: "WA"
        })

      {:ok, second_phone} =
        Glific.WAManagedPhones.create_wa_managed_phone(%{
          label: "second",
          phone: "919999900042",
          phone_id: 9_999_042,
          status: "active",
          organization_id: user.organization_id,
          contact_id: second_contact.id
        })

      wa_group =
        Fixtures.wa_group_fixture(%{
          organization_id: user.organization_id,
          wa_managed_phone_id: first_phone.id
        })

      Fixtures.wa_group_phone_fixture(%{
        wa_group_id: wa_group.id,
        wa_managed_phone_id: first_phone.id,
        organization_id: user.organization_id,
        is_primary: true,
        is_active: true
      })

      Fixtures.wa_group_phone_fixture(%{
        wa_group_id: wa_group.id,
        wa_managed_phone_id: second_phone.id,
        organization_id: user.organization_id,
        is_primary: false,
        is_active: true
      })

      %{wa_group: wa_group, first_phone: first_phone, second_phone: second_phone}
    end

    test "WAGroup.primaryPhone returns the primary managed phone", %{
      user: user,
      wa_group: wa_group,
      first_phone: first_phone
    } do
      result =
        auth_query_gql_by(:wa_group_with_phones, user,
          variables: %{"id" => to_string(wa_group.id)}
        )

      assert {:ok, query_data} = result
      primary = get_in(query_data, [:data, "waGroup", "waGroup", "primaryPhone"])
      assert primary["id"] == to_string(first_phone.id)
      assert primary["phone"] == first_phone.phone
    end

    test "WAGroup.phones returns both memberships with is_primary / is_active flags", %{
      user: user,
      wa_group: wa_group,
      first_phone: first_phone,
      second_phone: second_phone
    } do
      result =
        auth_query_gql_by(:wa_group_with_phones, user,
          variables: %{"id" => to_string(wa_group.id)}
        )

      assert {:ok, query_data} = result
      phones = get_in(query_data, [:data, "waGroup", "waGroup", "phones"])
      assert length(phones) == 2

      by_phone_id = Map.new(phones, &{&1["waManagedPhone"]["id"], &1})

      first = by_phone_id[to_string(first_phone.id)]
      assert first["isPrimary"] == true
      assert first["isActive"] == true

      second = by_phone_id[to_string(second_phone.id)]
      assert second["isPrimary"] == false
      assert second["isActive"] == true
    end

    test "setPrimaryPhone happy path: demote + promote, no warning", %{
      user: user,
      wa_group: wa_group,
      first_phone: first_phone,
      second_phone: second_phone
    } do
      result =
        auth_query_gql_by(:set_primary_phone, user,
          variables: %{
            "waGroupId" => to_string(wa_group.id),
            "waManagedPhoneId" => to_string(second_phone.id)
          }
        )

      assert {:ok, query_data} = result
      data = get_in(query_data, [:data, "setPrimaryPhone"])
      assert data["warning"] == nil
      assert data["waGroupPhone"]["isPrimary"] == true
      assert data["waGroupPhone"]["waManagedPhone"]["id"] == to_string(second_phone.id)

      assert WAGroups.primary_phone(wa_group.id).id == second_phone.id
      refute WAGroups.primary_phone(wa_group.id).id == first_phone.id
    end

    test "setPrimaryPhone returns a warning when target Maytapi status is not 'active'", %{
      user: user,
      wa_group: wa_group,
      second_phone: second_phone
    } do
      second_phone
      |> Glific.WAGroup.WAManagedPhone.changeset(%{status: "loading"})
      |> Glific.Repo.update!()

      result =
        auth_query_gql_by(:set_primary_phone, user,
          variables: %{
            "waGroupId" => to_string(wa_group.id),
            "waManagedPhoneId" => to_string(second_phone.id)
          }
        )

      assert {:ok, query_data} = result
      data = get_in(query_data, [:data, "setPrimaryPhone"])
      assert data["waGroupPhone"]["isPrimary"] == true
      assert data["warning"] =~ "loading"
    end

    test "setPrimaryPhone errors when no membership exists for the (group, phone) pair", %{
      user: user,
      wa_group: wa_group
    } do
      {:ok, ghost_contact} =
        Contacts.maybe_create_contact(%{
          phone: "919999900099",
          organization_id: user.organization_id,
          contact_type: "WA"
        })

      {:ok, ghost_phone} =
        Glific.WAManagedPhones.create_wa_managed_phone(%{
          label: "ghost",
          phone: "919999900099",
          phone_id: 9_999_099,
          status: "active",
          organization_id: user.organization_id,
          contact_id: ghost_contact.id
        })

      result =
        auth_query_gql_by(:set_primary_phone, user,
          variables: %{
            "waGroupId" => to_string(wa_group.id),
            "waManagedPhoneId" => to_string(ghost_phone.id)
          }
        )

      assert {:ok, query_data} = result
      [error] = query_data[:errors]
      assert error.message =~ "No membership"
    end

    test "setPrimaryPhone errors when target membership is inactive", %{
      user: user,
      wa_group: wa_group,
      second_phone: second_phone
    } do
      Glific.Repo.get_by(Glific.Groups.WAGroupPhone, %{
        wa_group_id: wa_group.id,
        wa_managed_phone_id: second_phone.id
      })
      |> Glific.Groups.WAGroupPhone.changeset(%{is_active: false})
      |> Glific.Repo.update!()

      result =
        auth_query_gql_by(:set_primary_phone, user,
          variables: %{
            "waGroupId" => to_string(wa_group.id),
            "waManagedPhoneId" => to_string(second_phone.id)
          }
        )

      assert {:ok, query_data} = result
      [error] = query_data[:errors]
      assert error.message =~ "inactive"
    end

    test "setPrimaryPhone is rejected for non-admin roles (manager)", %{
      manager: manager,
      wa_group: wa_group,
      second_phone: second_phone
    } do
      result =
        auth_query_gql_by(:set_primary_phone, manager,
          variables: %{
            "waGroupId" => to_string(wa_group.id),
            "waManagedPhoneId" => to_string(second_phone.id)
          }
        )

      assert {:ok, query_data} = result
      [error] = query_data[:errors]
      assert error.message =~ "Unauthorized" or error.message =~ "permission"
    end
  end
end
