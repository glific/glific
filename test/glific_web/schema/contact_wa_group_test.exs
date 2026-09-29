defmodule GlificWeb.Schema.ContactWaGroupTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Contacts,
    Fixtures,
    Groups,
    Groups.CollectionPrimaryPhone,
    Groups.ContactWAGroups,
    Groups.WAGroupPhone,
    Groups.WAGroups,
    Groups.WaGroupsCollections,
    Jobs.UserJob,
    Partners,
    Repo,
    Seeds.SeedsDev,
    WAGroup.WAManagedPhone
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

  load_gql(:import_members, GlificWeb.Schema, "assets/gql/wa_groups/import.gql")

  load_gql(
    :set_primary_phone_for_collection,
    GlificWeb.Schema,
    "assets/gql/contact_wa_groups/set_primary_phone_for_collection.gql"
  )

  load_gql(
    :collection_primary_report,
    GlificWeb.Schema,
    "assets/gql/contact_wa_groups/collection_primary_report.gql"
  )

  test "create wa group contacts", %{user: user} do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

    wa_group =
      Fixtures.wa_group_with_primary_fixture(%{
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
      Fixtures.wa_group_with_primary_fixture(%{
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
          body: Jason.encode!(%{success: true})
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
      Fixtures.wa_group_with_primary_fixture(%{
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
    Tesla.Mock.mock(fn
      %{
        method: :get,
        url: "https://api.maytapi.com/api/3fa22108-f464-41e5-81d9-d8a298854430/listPhones"
      } ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body:
             ~s([{"id":242,"number":"918454812345","status":"active","type":"whatsapp","name":""}])
         }}

      %{
        method: :get,
        url: "https://api.maytapi.com/api/3fa22108-f464-41e5-81d9-d8a298854430/242/getGroups"
      } ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: ~s({"count":0,"data":[],"limit":500,"success":true,"total":0})
         }}
    end)

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
      Fixtures.wa_group_with_primary_fixture(%{
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
        |> WAManagedPhone.changeset(%{status: "active"})
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
        Fixtures.wa_group_with_primary_fixture(%{
          organization_id: user.organization_id,
          wa_managed_phone_id: first_phone.id
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
      assert data["primaryPhone"]["isPrimary"] == true
      assert data["primaryPhone"]["waManagedPhone"]["id"] == to_string(second_phone.id)

      assert WAGroups.primary_phone(wa_group.id).id == second_phone.id
      refute WAGroups.primary_phone(wa_group.id).id == first_phone.id
    end

    test "setPrimaryPhone returns a warning when target Maytapi status is not 'active'", %{
      user: user,
      wa_group: wa_group,
      second_phone: second_phone
    } do
      second_phone
      |> WAManagedPhone.changeset(%{status: "loading"})
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
      assert data["primaryPhone"]["isPrimary"] == true
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
      assert error.message =~ "not a member of the group"
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
      |> WAGroupPhone.changeset(%{is_active: false})
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
      assert error.message =~ "removed from the group"
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

  describe "importWaGroupContacts" do
    setup %{glific_admin: user} do
      wa_managed_phone =
        Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

      wa_group =
        Fixtures.wa_group_fixture(%{
          organization_id: user.organization_id,
          wa_managed_phone_id: wa_managed_phone.id
        })

      %{wa_group: wa_group}
    end

    test "an admin kicks off a background CSV import", %{glific_admin: user, wa_group: wa_group} do
      result =
        auth_query_gql_by(:import_members, user,
          variables: %{
            "waGroupId" => to_string(wa_group.id),
            "type" => "DATA",
            "data" => "phone\n919900112233\n"
          }
        )

      assert {:ok, query_data} = result
      assert is_nil(query_data[:errors])
      status = get_in(query_data, [:data, "importWaGroupContacts", "status"])
      assert status =~ "in progress"
    end

    test "is rejected for a non-admin", %{staff: user, wa_group: wa_group} do
      result =
        auth_query_gql_by(:import_members, user,
          variables: %{
            "waGroupId" => to_string(wa_group.id),
            "type" => "DATA",
            "data" => "phone\n919900112233\n"
          }
        )

      assert {:ok, query_data} = result
      [error] = query_data[:errors]
      assert error.message =~ "Unauthorized" or error.message =~ "permission"
    end

    test "rejects a wa_group the caller's org does not own", %{
      glific_admin: user,
      wa_group: wa_group
    } do
      # the org-scoped by-id lookup must reject an id outside the caller's org
      result =
        auth_query_gql_by(:import_members, user,
          variables: %{
            "waGroupId" => to_string(wa_group.id + 1_000_000),
            "type" => "DATA",
            "data" => "phone\n919900112233\n"
          }
        )

      assert {:ok, query_data} = result
      errors = get_in(query_data, [:data, "importWaGroupContacts", "errors"])
      assert [%{"message" => message} | _] = errors
      assert message =~ "Resource not found"
    end
  end

  # Add a WA group to `collection`, optionally seeding the phone's membership.
  defp add_collection_group(collection, phone, organization_id, suffix, member?) do
    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: organization_id,
        wa_managed_phone_id: phone.id,
        label: "Group #{suffix}",
        bsp_id: "coll-#{suffix}@g.us"
      })

    {:ok, _} =
      WaGroupsCollections.create_wa_groups_collection(%{
        group_id: collection.id,
        wa_group_id: wa_group.id,
        organization_id: organization_id
      })

    if member? do
      Fixtures.wa_group_phone_fixture(%{
        wa_group_id: wa_group.id,
        wa_managed_phone_id: phone.id,
        organization_id: organization_id,
        is_active: true,
        is_primary: false
      })
    end

    wa_group
  end

  describe "setPrimaryPhoneForCollection" do
    setup %{user: user} do
      organization_id = user.organization_id

      {:ok, phone} =
        %{organization_id: organization_id}
        |> Fixtures.wa_managed_phone_fixture()
        |> WAManagedPhone.changeset(%{status: "active"})
        |> Repo.update()

      {:ok, collection} =
        Groups.create_group(%{label: "Broadcast collection", organization_id: organization_id})

      %{organization_id: organization_id, phone: phone, collection: collection}
    end

    test "enqueues a background job when the phone is a member of a group", %{
      user: user,
      organization_id: organization_id,
      phone: phone,
      collection: collection
    } do
      add_collection_group(collection, phone, organization_id, 1, true)

      result =
        auth_query_gql_by(:set_primary_phone_for_collection, user,
          variables: %{
            "collectionId" => to_string(collection.id),
            "waManagedPhoneId" => to_string(phone.id)
          }
        )

      assert {:ok, query_data} = result
      data = get_in(query_data, [:data, "setPrimaryPhoneForCollection"])
      assert data["status"] =~ "background"
      assert data["userJobId"]

      assert [%UserJob{type: type}] =
               UserJob.list_user_jobs(%{filter: %{organization_id: organization_id}})

      assert type == CollectionPrimaryPhone.job_type()
    end

    test "errors (no job) when the phone is a member of no group in the collection", %{
      user: user,
      organization_id: organization_id,
      phone: phone,
      collection: collection
    } do
      add_collection_group(collection, phone, organization_id, 2, false)

      result =
        auth_query_gql_by(:set_primary_phone_for_collection, user,
          variables: %{
            "collectionId" => to_string(collection.id),
            "waManagedPhoneId" => to_string(phone.id)
          }
        )

      assert {:ok, query_data} = result
      assert query_data[:errors]
      assert UserJob.list_user_jobs(%{filter: %{organization_id: organization_id}}) == []
    end

    test "is rejected for non-admin roles (manager)", %{
      manager: manager,
      organization_id: organization_id,
      phone: phone,
      collection: collection
    } do
      add_collection_group(collection, phone, organization_id, 3, true)

      result =
        auth_query_gql_by(:set_primary_phone_for_collection, manager,
          variables: %{
            "collectionId" => to_string(collection.id),
            "waManagedPhoneId" => to_string(phone.id)
          }
        )

      assert {:ok, query_data} = result
      [error] = query_data[:errors]
      assert error.message =~ "Unauthorized" or error.message =~ "permission"
    end

    test "waGroupCollectionPrimaryReport returns the skip CSV for a completed job", %{
      user: user,
      organization_id: organization_id
    } do
      user_job =
        UserJob.create_user_job(%{
          status: "success",
          type: CollectionPrimaryPhone.job_type(),
          total_tasks: 1,
          tasks_done: 1,
          all_tasks_created: true,
          organization_id: organization_id,
          errors: %{"errors" => %{"Group X (#7)" => "not_a_member"}}
        })

      result =
        auth_query_gql_by(:collection_primary_report, user,
          variables: %{"userJobId" => to_string(user_job.id)}
        )

      assert {:ok, query_data} = result
      csv = get_in(query_data, [:data, "waGroupCollectionPrimaryReport", "csvRows"])
      assert csv =~ "Group,Reason"
      assert csv =~ "Group X (#7),not_a_member"
    end
  end
end
