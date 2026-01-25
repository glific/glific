defmodule GlificWeb.Schema.ContactTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Contacts.ImportWorker,
    Fixtures,
    Flows,
    Messages.Message,
    Profiles.Profile,
    Repo,
    Seeds.SeedsDev,
    State
  }

  setup do
    Tesla.Mock.mock_global(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200
        }

      %{method: :post} ->
        %Tesla.Env{
          status: 200
        }
    end)

    :ok
  end

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/contacts/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/contacts/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/contacts/by_id.gql")
  load_gql(:by_phone, GlificWeb.Schema, "assets/gql/contacts/by_phone.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/contacts/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/contacts/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/contacts/delete.gql")
  load_gql(:contact_location, GlificWeb.Schema, "assets/gql/contacts/contact_location.gql")
  load_gql(:optin_contact, GlificWeb.Schema, "assets/gql/contacts/optin_contact.gql")
  load_gql(:import_contacts, GlificWeb.Schema, "assets/gql/contacts/import.gql")
  load_gql(:move_contacts, GlificWeb.Schema, "assets/gql/contacts/move.gql")
  load_gql(:sim_get, GlificWeb.Schema, "assets/gql/contacts/simulator_get.gql")
  load_gql(:sim_rel, GlificWeb.Schema, "assets/gql/contacts/simulator_release.gql")

  load_gql(
    :contact_history_list,
    GlificWeb.Schema,
    "assets/gql/contacts/contact_history_list.gql"
  )

  load_gql(
    :count_contact_history,
    GlificWeb.Schema,
    "assets/gql/contacts/count_contact_history.gql"
  )

  test "contacts field returns list of contacts", %{staff: user} do
    result = auth_query_gql_by(:list, user)
    assert {:ok, query_data} = result

    contacts = get_in(query_data, [:data, "contacts"])
    assert length(contacts) > 0

    res =
      contacts
      |> get_in([Access.all(), "name"])
      |> Enum.find(fn name -> name == "NGO Main Account" end)

    assert res == "NGO Main Account"

    [contact | _] = contacts
    assert contact["groups"] == []
  end

  test "contacts field returns list of contacts in asc order", %{staff: user} do
    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "ASC"}})
    assert {:ok, query_data} = result

    contacts = get_in(query_data, [:data, "contacts"])
    assert length(contacts) > 0

    [contact_a, contact_b | _] = contacts

    # sometime the contact we create from the user is sorted before our friend
    # Adelle, hence checking the first two contacts
    assert get_in(contact_a, ["name"]) == "Adelle Cavin" or
             get_in(contact_b, ["name"]) == "Adelle Cavin"
  end

  test "contacts field obeys limit and offset", %{staff: user} do
    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "contacts"])) == 1

    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 3, "offset" => 1}})

    assert {:ok, query_data} = result

    contacts = get_in(query_data, [:data, "contacts"])
    assert length(contacts) == 3

    # lets make sure we don't get Test as a contact
    assert get_in(contacts, [Access.at(0), "name"]) != "Test"
    assert get_in(contacts, [Access.at(1), "name"]) != "Test"
    assert get_in(contacts, [Access.at(2), "name"]) != "Test"
  end

  test "count returns the number of contacts", %{staff: user} do
    {:ok, query_data} = auth_query_gql_by(:count, user)
    # we are adding 5 contacts, but we don't know initial state of DB, hence using >=
    assert get_in(query_data, [:data, "countContacts"]) >= 5

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"name" => "This contact should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countContacts"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"name" => "NGO Main Account"}})

    assert get_in(query_data, [:data, "countContacts"]) == 1
  end

  test "contact by id returns one contact or nil", %{staff: user} do
    name = "NGO Main Account"
    {:ok, contact} = Repo.fetch_by(Contact, %{name: name, organization_id: user.organization_id})

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => contact.id})
    assert {:ok, query_data} = result

    fetched_contact = get_in(query_data, [:data, "contact", "contact"])
    assert fetched_contact["name"] == name
    # staff role should not have access to phone
    assert fetched_contact["phone"] == ""
    assert fetched_contact["maskedPhone"] != contact.phone

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "contact", "errors", Access.at(0), "message"])
    assert message == "Contact not found or permission denied."
  end

  test "contact by id returns one contact with phone for manager/admin role", %{manager: user} do
    name = "NGO Main Account"
    {:ok, contact} = Repo.fetch_by(Contact, %{name: name, organization_id: user.organization_id})

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => contact.id})
    assert {:ok, query_data} = result

    fetched_contact = get_in(query_data, [:data, "contact", "contact"])
    assert fetched_contact["phone"] == contact.phone
    assert fetched_contact["maskedPhone"] != nil
  end

  test "contact by phone returns one contact for manager/admin role", %{manager: user} do
    name = "NGO Main Account"
    {:ok, contact} = Repo.fetch_by(Contact, %{name: name, organization_id: user.organization_id})

    result = auth_query_gql_by(:by_phone, user, variables: %{"phone" => contact.phone})
    assert {:ok, query_data} = result

    fetched_contact = get_in(query_data, [:data, "contactByPhone", "contact"])
    assert fetched_contact["id"] == "#{contact.id}"
    assert fetched_contact["maskedPhone"] != nil
  end

  test "contact by phone returns error if contact not found", %{manager: user} do
    result = auth_query_gql_by(:by_phone, user, variables: %{"phone" => "Invalid phone"})
    assert {:ok, query_data} = result
    fetched_contact = get_in(query_data, [:data, "contactByPhone", "contact"])
    assert fetched_contact == nil
    assert is_list(get_in(query_data, [:data, "contactByPhone", "errors"]))
  end

  test "create a contact with profile", %{manager: user} do
    profile = Repo.get_by!(Profile, name: "user")

    name = "Contact Test Name Uno"
    phone = "1-415-555-1212"
    active_profile_id = profile.id

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{"name" => name, "phone" => phone, "active_profile_id" => active_profile_id}
        }
      )

    assert {:ok, query_data} = result
    contact = get_in(query_data, [:data, "createContact", "contact"])
    assert Map.get(contact, "name") == name
  end

  test "create a contact and test possible scenarios and errors", %{manager: user} do
    name = "Contact Test Name Uno"
    phone = "1-415-555-1212"

    result =
      auth_query_gql_by(:create, user,
        variables: %{"input" => %{"name" => name, "phone" => phone}}
      )

    assert {:ok, query_data} = result
    contact = get_in(query_data, [:data, "createContact", "contact"])
    assert Map.get(contact, "name") == name
    assert Map.get(contact, "phone") == phone

    # try creating the same contact twice
    _ =
      auth_query_gql_by(:create, user,
        variables: %{"input" => %{"name" => name, "phone" => phone}}
      )

    result =
      auth_query_gql_by(:create, user,
        variables: %{"input" => %{"name" => name, "phone" => phone}}
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "createContact", "errors", Access.at(0), "message"])
    assert message =~ "has already been taken"
  end

  test "User delete", %{manager: user} do
    user = Map.put(user, :roles, [:Glific_admin])
    test_name = "test"
    test_phone = "test phone"
    # Test success for deleting a created contact
    data = "name,phone,language,opt_in,delete,\n#{test_name},#{test_phone},english,,1"

    result =
      auth_query_gql_by(:import_contacts, user,
        variables: %{
          "type" => "DATA",
          "data" => data
        }
      )

    assert {:ok, _} = result

    count = Contacts.count_contacts(%{filter: %{phone: test_phone}})
    assert count == 0
  end

  test "moving contacts and test possible scenarios and errors", %{manager: user} do
    data = "name,phone,collection\r\nJohn Doe,9876543210_4,Bleach\r\nUkitake,918979120220,Bleach"

    result =
      auth_query_gql_by(:move_contacts, user,
        variables: %{
          "type" => "DATA",
          "data" => data
        }
      )

    assert {:ok, _query_data} = result
    assert_enqueued(worker: ImportWorker, prefix: "global")

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :contact_import, with_scheduled: true)

    assert Contacts.count_contacts(%{filter: %{phone: "918979120220"}}) == 0
  end

  test "import contacts and test possible scenarios and errors", %{manager: user} do
    test_name = "test"
    test_phone = "test phone"
    user = Map.put(user, :roles, [:glific_admin])

    data =
      "name,phone,language,opt_in,delete\n#{test_name} updated,#{test_phone},english,2021-03-09 12:34:25,0"

    # Test success for creating a contact without opt-in
    result =
      auth_query_gql_by(:import_contacts, user,
        variables: %{
          "type" => "DATA",
          "data" => data,
          "group_label" => "collection"
        }
      )

    assert {:ok, _} = result
    assert_enqueued(worker: ImportWorker, prefix: "global")

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :contact_import, with_scheduled: true)

    # Will fail since contact is not a valid phone number
    assert Contacts.count_contacts(%{filter: %{phone: test_phone}}) == 0
    assert Contacts.count_contacts(%{filter: %{term: test_phone}}) == 0

    # Test success for creating a contact with opt-in
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200
        }
    end)

    test_name = "test2"
    test_phone = "+919917443992"

    data =
      "name,phone,language,opt_in,collection\n#{test_name},#{test_phone},english,2021-03-09 12:34:25,collection"

    result =
      auth_query_gql_by(:import_contacts, user,
        variables: %{
          "type" => "DATA",
          "data" => data,
          "group_label" => "collection"
        }
      )

    assert {:ok, _} = result
    assert_enqueued(worker: ImportWorker, prefix: "global")

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :contact_import, with_scheduled: true)

    contact = assert Contacts.get_contact_by_phone!(test_phone)
    assert contact.optin_method == "Import"
    count = Contacts.count_contacts(%{filter: %{phone: test_phone}})
    assert count == 1

    # Test success for updating a contact, the contact won't get uploaded due to
    #  test_phone being invalid
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200
        }
    end)

    test_name = "test2"
    test_phone = "test phone2"

    data =
      "name,phone,language,opt_in,delete,collection\n#{test_name} updated,#{test_phone},english,2021-03-09 12:34:25,0,collection"

    result =
      auth_query_gql_by(:import_contacts, user,
        variables: %{
          "type" => "DATA",
          "data" => data,
          "group_label" => "collection"
        }
      )

    assert {:ok, _} = result
    assert_enqueued(worker: ImportWorker, prefix: "global")

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :contact_import, with_scheduled: true)

    assert Contacts.count_contacts(%{filter: %{name: "#{test_name} updated"}}) == 0
    assert Contacts.count_contacts(%{filter: %{term: "#{test_name} updated"}}) == 0

    # # Test success for uploading contact through url
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200
        }

      %{method: :get} ->
        %Tesla.Env{
          body:
            "name,phone,Language,opt_in,delete,collection\r\nuploaded_contact,+919876543211,english,2021-03-09 12:34:25,,collection",
          status: 200
        }
    end)

    result =
      auth_query_gql_by(:import_contacts, user,
        variables: %{
          "type" => "URL",
          "data" => "https://storage.cloud.google.com/test.csv",
          "group_label" => "collection"
        }
      )

    assert {:ok, _} = result
    assert_enqueued(worker: ImportWorker, prefix: "global")

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :contact_import, with_scheduled: true)

    count = Contacts.count_contacts(%{filter: %{name: "uploaded_contact"}})
    assert count == 1
  end

  test "Test success for uploading contact through filepath", %{manager: user} do
    user = Map.put(user, :roles, [:glific_admin])

    file =
      System.tmp_dir!()
      |> Path.join("fixture.csv")
      |> File.open!([:write, :utf8])

    [
      ~w(name phone Language opt_in collection),
      ["test", "+919876543210", "english", "2021-03-09 12:34:25", "collection"]
    ]
    |> CSV.encode()
    |> Enum.each(&IO.write(file, &1))

    file_name = System.tmp_dir!() |> Path.join("fixture.csv")

    result =
      auth_query_gql_by(:import_contacts, user,
        variables: %{
          "type" => "FILE_PATH",
          "data" => file_name,
          "group_label" => "collection"
        }
      )

    assert {:ok, _} = result
    assert_enqueued(worker: ImportWorker, prefix: "global")

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :contact_import, with_scheduled: true)

    count = Contacts.count_contacts(%{filter: %{name: "test"}})
    assert count == 1
  end

  test "test success for uploading contact for different csv", %{manager: user} do
    user = Map.put(user, :roles, [:glific_admin])

    file =
      System.tmp_dir!()
      |> Path.join("fixture.csv")
      |> File.open!([:write, :utf8])

    [
      ~w(name phone language opt_in delete collection),
      ["test", "+919989329297", "english", "2021-03-09 12:34:25", "0", "collection"]
    ]
    |> CSV.encode()
    |> Enum.each(&IO.write(file, &1))

    file_name = System.tmp_dir!() |> Path.join("fixture.csv")

    result =
      auth_query_gql_by(:import_contacts, user,
        variables: %{
          "type" => "FILE_PATH",
          "data" => file_name,
          "group_label" => "collection"
        }
      )

    assert {:ok, _} = result
    assert_enqueued(worker: ImportWorker, prefix: "global")

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :contact_import, with_scheduled: true)

    count = Contacts.count_contacts(%{filter: %{name: "test"}})
    assert count == 1
  end

  test "test success for uploading contact for admin, contact won't upload since phone is not a valid one",
       %{manager: user} do
    user = Map.put(user, :roles, [:admin])

    test_name = "test2"
    test_phone = "test phone2"

    data =
      "name,phone,language,opt_in,delete,collection\n#{test_name} updated,#{test_phone},english,2021-03-09 12:34:25,0,collection"

    result =
      auth_query_gql_by(:import_contacts, user,
        variables: %{
          "type" => "DATA",
          "data" => data,
          "group_label" => "collection"
        }
      )

    assert {:ok, _} = result
    assert_enqueued(worker: ImportWorker, prefix: "global")

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :contact_import, with_scheduled: true)

    count = Contacts.count_contacts(%{filter: %{name: "test"}})
    assert count == 0
  end

  test "update a contact and test possible scenarios and errors", %{staff: user, manager: manager} do
    {:ok, contact} =
      Repo.fetch_by(Contact, %{name: "NGO Main Account", organization_id: user.organization_id})

    name = "Contact Test Name New"
    phone = "1-415-555-1212 New"

    result =
      auth_query_gql_by(:update, user,
        variables: %{"id" => contact.id, "input" => %{"name" => name}}
      )

    assert {:ok, query_data} = result

    new_name = get_in(query_data, [:data, "updateContact", "contact", "name"])
    assert new_name == name

    # create a temp contact with a new phone number
    _ =
      auth_query_gql_by(:create, manager,
        variables: %{"input" => %{"name" => "Yet another name", "phone" => phone <> " New"}}
      )

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => contact.id,
          "input" => %{"name" => name, "phone" => phone <> " New"}
        }
      )

    # ensure we cannot update an existing contact's phone

    assert {:ok, query_data} = result

    error_message = hd(query_data.errors).message

    assert error_message =~ "Cannot modify read-only fields"
  end

  test "delete a contact", %{manager: user} do
    # Delete a random contact
    {:ok, contact} =
      Repo.fetch_by(Contact, %{name: "Chrissy Cron", organization_id: user.organization_id})

    result = auth_query_gql_by(:delete, user, variables: %{"id" => contact.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteContact", "errors"]) == nil

    result = auth_query_gql_by(:delete, user, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteContact", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "get contact location", %{manager: user} do
    {:ok, contact} =
      Repo.fetch_by(Contact, %{name: "Chrissy Cron", organization_id: user.organization_id})

    {:ok, message} =
      Repo.fetch_by(Message, %{
        body: "Default message body",
        organization_id: user.organization_id
      })

    {:ok, location} =
      Contacts.create_location(%{
        message_id: message.id,
        contact_id: contact.id,
        longitude: Faker.Address.longitude(),
        latitude: Faker.Address.latitude(),
        organization_id: user.organization_id
      })

    # get contact location
    result = auth_query_gql_by(:contact_location, user, variables: %{"id" => contact.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "contactLocation", "longitude"]) == location.longitude
  end

  test "search contacts field returns list of contacts with options set", %{staff: user} do
    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "contacts"])) == 1

    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 3, "offset" => 1}})

    assert {:ok, query_data} = result

    contacts = get_in(query_data, [:data, "contacts"])
    assert length(contacts) == 3

    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "ASC"}})
    assert {:ok, query_data} = result

    contacts = get_in(query_data, [:data, "contacts"])
    assert length(contacts) >= 1
    [contact_a, contact_b | _] = contacts

    # sometime the contact we create from the user is sorted before our friend
    # Adelle, hence checking the first two contacts
    assert get_in(contact_a, ["name"]) == "Adelle Cavin" or
             get_in(contact_b, ["name"]) == "Adelle Cavin"
  end

  test "search contacts field obeys group filters", %{staff: user} do
    [cg1, _cg2, cg3] = Fixtures.group_contacts_fixture(%{organization_id: user.organization_id})

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"includeGroups" => ["#{cg1.group_id}"]}
        }
      )

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "contacts"])) == 2

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"includeGroups" => ["99999"]}
        }
      )

    assert {:ok, query_data} = result

    contacts = get_in(query_data, [:data, "contacts"])
    assert contacts == []

    # contact should not be repeated in the search list
    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{
            "includeGroups" => ["#{cg1.group_id}", "#{cg3.group_id}"]
          }
        }
      )

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "contacts"])) == 2
  end

  test "search contacts field obeys exclude group filters", %{staff: user} do
    [cg1, _cg2, cg3] = Fixtures.group_contacts_fixture(%{organization_id: user.organization_id})

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"excludeGroups" => ["#{cg1.group_id}"]}
        }
      )

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "contacts"])) == 13

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"excludeGroups" => ["99999"]}
        }
      )

    assert {:ok, query_data} = result

    assert length(get_in(query_data, [:data, "contacts"])) == 15

    # contact should not be repeated in the search list
    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{
            "excludeGroups" => ["#{cg1.group_id}", "#{cg3.group_id}"]
          }
        }
      )

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "contacts"])) == 13

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{
            "excludeGroups" => []
          }
        }
      )

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "contacts"])) == 15
  end

  test "search contacts field obeys wa_group filters", %{staff: user} do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

    cwg1 =
      Fixtures.contact_wa_group_fixture(%{
        organization_id: user.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"includeWaGroups" => ["#{cwg1.wa_group_id}"]}
        }
      )

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "contacts"])) == 1

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"includeWaGroups" => ["99999"]}
        }
      )

    assert {:ok, query_data} = result

    contacts = get_in(query_data, [:data, "contacts"])
    assert contacts == []
  end

  test "search contacts field obeys exclude wa_group filters", %{staff: user} do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

    cwg1 =
      Fixtures.contact_wa_group_fixture(%{
        organization_id: user.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"excludeWaGroups" => ["#{cwg1.wa_group_id}"]}
        }
      )

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "contacts"])) == 15

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"excludeWaGroups" => ["99999"]}
        }
      )

    assert {:ok, query_data} = result

    assert length(get_in(query_data, [:data, "contacts"])) == 16

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"excludeWaGroups" => []}
        }
      )

    assert {:ok, query_data} = result

    assert length(get_in(query_data, [:data, "contacts"])) == 16
  end

  test "search contacts field obeys tag filters", %{staff: user} do
    [ct1, _ct2, _ct3] = Fixtures.contact_tags_fixture(%{organization_id: user.organization_id})

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{
            "includeTags" => ["#{ct1.tag_id}"]
          }
        }
      )

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "contacts"])) == 2

    # search a contact with in a group and having multiple tags
    [_cg1, _cg2, cg3] = Fixtures.group_contacts_fixture(%{organization_id: user.organization_id})

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{
            "includeTags" => ["#{ct1.tag_id}"],
            "includeGroups" => ["#{cg3.group_id}"]
          }
        }
      )

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "contacts"])) == 1
    assert get_in(query_data, [:data, "contacts", Access.at(0), "id"]) == "#{cg3.contact_id}"
  end

  test "search contacts should take care of empty list of group/tag filter input", %{staff: user} do
    [_cg1, _cg2, _cg3] = Fixtures.group_contacts_fixture(%{organization_id: user.organization_id})

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"includeGroups" => []}
        }
      )

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "contacts"]) != []

    [_ct1, _ct2, _ct3] = Fixtures.contact_tags_fixture(%{organization_id: user.organization_id})

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"includeTags" => []}
        }
      )

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "contacts"]) != []
  end

  test "optin contact and test possible scenarios and errors", %{manager: manager} do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 202
        }
    end)

    result = auth_query_gql_by(:optin_contact, manager, variables: %{"phone" => "test phone"})

    assert {:ok, query_data} = result

    contact = get_in(query_data, [:data, "optinContact", "contact"])
    assert contact["bspStatus"] == "HSM"
    assert contact["name"] == nil

    # add name with phone
    result =
      auth_query_gql_by(:optin_contact, manager,
        variables: %{"name" => "contact name", "phone" => "test phone 2"}
      )

    assert {:ok, query_data} = result

    contact = get_in(query_data, [:data, "optinContact", "contact"])
    assert contact["bspStatus"] == "HSM"
    assert contact["name"] == "contact name"
    contact_id = contact["id"]

    # trying to optin already existing phone should update the existing contact
    result =
      auth_query_gql_by(:optin_contact, manager,
        variables: %{"name" => "contact name", "phone" => "test phone 2"}
      )

    assert {:ok, query_data} = result

    contact = get_in(query_data, [:data, "optinContact", "contact"])
    assert contact_id == contact["id"]
  end

  test "simulator get returns a simulator contact",
       %{staff: staff, manager: manager, user: user} do
    State.reset(user.organization_id)

    # we should get 5 simulators
    result = auth_query_gql_by(:sim_get, staff, variables: %{})
    assert {:ok, query_data} = result
    assert String.contains?(get_in(query_data, [:data, "simulatorGet", "name"]), "Simulator")

    result = auth_query_gql_by(:sim_get, manager, variables: %{})
    assert {:ok, query_data} = result
    assert String.contains?(get_in(query_data, [:data, "simulatorGet", "name"]), "Simulator")

    result = auth_query_gql_by(:sim_get, user, variables: %{})
    assert {:ok, query_data} = result
    assert String.contains?(get_in(query_data, [:data, "simulatorGet", "name"]), "Simulator")

    user = Map.put(user, :fingerprint, Ecto.UUID.generate())
    result = auth_query_gql_by(:sim_get, user, variables: %{})
    assert {:ok, query_data} = result
    assert String.contains?(get_in(query_data, [:data, "simulatorGet", "name"]), "Simulator")

    user = Map.put(user, :fingerprint, Ecto.UUID.generate())
    result = auth_query_gql_by(:sim_get, user, variables: %{})
    assert {:ok, query_data} = result
    assert String.contains?(get_in(query_data, [:data, "simulatorGet", "name"]), "Simulator")

    user = Map.put(user, :fingerprint, Ecto.UUID.generate())
    result = auth_query_gql_by(:sim_get, user, variables: %{})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "simulatorGet"]) == nil

    # now release a simulator and try again
    result = auth_query_gql_by(:sim_rel, staff, variables: %{})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "simulatorRelease"]) == nil

    user = Map.put(user, :fingerprint, Ecto.UUID.generate())
    result = auth_query_gql_by(:sim_get, user, variables: %{})
    assert {:ok, query_data} = result
    assert String.contains?(get_in(query_data, [:data, "simulatorGet", "name"]), "Simulator")
  end

  test "contacts history returns list of contacts history in asc order", %{staff: user} = attrs do
    profile = Fixtures.profile_fixture()
    contact = Contacts.get_contact!(profile.contact_id)
    [flow | _tail] = Flows.list_flows(attrs)
    {:ok, _flow} = Flows.start_contact_flow(flow, contact)

    result =
      auth_query_gql_by(:contact_history_list, user,
        variables: %{
          "opts" => %{"order" => "ASC"},
          "filter" => %{"contact_id" => contact.id}
        }
      )

    assert {:ok, query_data} = result
    contact_history = get_in(query_data, [:data, "contactHistory"])
    assert length(contact_history) > 0

    result =
      auth_query_gql_by(:contact_history_list, user,
        variables: %{
          "filter" => %{"profile_id" => profile.id}
        }
      )

    assert {:ok, query_data} = result
    contact_history = get_in(query_data, [:data, "contactHistory"])
    assert length(contact_history) > 0

    result =
      auth_query_gql_by(:contact_history_list, user,
        variables: %{
          "filter" => %{"event_label" => "Flow Started"}
        }
      )

    assert {:ok, query_data} = result
    contact_history = get_in(query_data, [:data, "contactHistory"])
    assert length(contact_history) > 0

    result =
      auth_query_gql_by(:contact_history_list, user,
        variables: %{
          "opts" => %{"order" => "DESC"}
        }
      )

    assert {:ok, query_data} = result
    [contact_history | _] = get_in(query_data, [:data, "contactHistory"])
    assert contact_history["eventLabel"] == "Flow Started"
  end

  test "count contacts history returns count of contacts history", %{staff: user} = attrs do
    [contact | _tail] = Contacts.list_contacts(attrs)
    [flow | _tail] = Flows.list_flows(attrs)
    {:ok, _flow} = Flows.start_contact_flow(flow, contact)

    result =
      auth_query_gql_by(:count_contact_history, user,
        variables: %{
          "filter" => %{"contact_id" => contact.id}
        }
      )

    assert {:ok, query_data} = result
    count = get_in(query_data, [:data, "countContactHistory"])
    assert count > 0

    count_from_db =
      Contacts.count_contact_history(
        attrs
        |> Map.merge(%{
          "filter" => %{"contact_id" => contact.id}
        })
      )

    assert count_from_db == count
    assert get_in(query_data, [:data, "countContactHistory"]) > 0
  end
end
