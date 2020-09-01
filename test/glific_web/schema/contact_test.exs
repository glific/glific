defmodule GlificWeb.Schema.ContactTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Fixtures,
    Messages.Message,
    Repo,
    Seeds.SeedsDev
  }

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
  load_gql(:create, GlificWeb.Schema, "assets/gql/contacts/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/contacts/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/contacts/delete.gql")
  load_gql(:contact_location, GlificWeb.Schema, "assets/gql/contacts/contact_location.gql")

  test "contacts field returns list of contacts", %{user: user} do
    result = auth_query_gql_by(:list, user)
    assert {:ok, query_data} = result

    contacts = get_in(query_data, [:data, "contacts"])
    assert length(contacts) > 0

    res = contacts |> get_in([Access.all(), "name"]) |> Enum.find(fn x -> x == "Glific Admin" end)

    assert res == "Glific Admin"

    [contact | _] = contacts
    assert contact["groups"] == []
  end

  test "contacts field returns list of contacts in asc order", %{user: user} do
    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "ASC"}})
    assert {:ok, query_data} = result

    contacts = get_in(query_data, [:data, "contacts"])
    assert length(contacts) > 0

    [contact_a, contact_b | _] = contacts

    # sometime the contact we create from the user is sorted before our friend
    # adelle, hence checking the first two contacts
    assert get_in(contact_a, ["name"]) == "Adelle Cavin" or
    get_in(contact_b, ["name"]) == "Adelle Cavin"
  end

  test "contacts field obeys limit and offset", %{user: user} do
    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "contacts"])) == 1

    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 3, "offset" => 1}})

    assert {:ok, query_data} = result

    contacts = get_in(query_data, [:data, "contacts"])
    assert length(contacts) == 3

    # lets make sure we dont get Test as a contact
    assert get_in(contacts, [Access.at(0), "name"]) != "Test"
    assert get_in(contacts, [Access.at(1), "name"]) != "Test"
    assert get_in(contacts, [Access.at(2), "name"]) != "Test"
  end

  test "count returns the number of contacts", %{user: user} do
    {:ok, query_data} = auth_query_gql_by(:count, user)
    # we are adding 5 contacts, but we dont know intial state of DB, hence using >=
    assert get_in(query_data, [:data, "countContacts"]) >= 5

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"name" => "This contact should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countContacts"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"name" => "Glific Admin"}})

    assert get_in(query_data, [:data, "countContacts"]) == 1
  end

  test "contact id returns one contact or nil", %{user: user} do
    name = "Glific Admin"
    {:ok, contact} = Repo.fetch_by(Contact, %{name: name, organization_id: user.organization_id})

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => contact.id})
    assert {:ok, query_data} = result

    contact = get_in(query_data, [:data, "contact", "contact", "name"])
    assert contact == name

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "contact", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "create a contact and test possible scenarios and errors", %{user: user} do
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
    assert message == "has already been taken"
  end

  test "update a contact and test possible scenarios and errors", %{user: user} do
    {:ok, contact} =
      Repo.fetch_by(Contact, %{name: "Glific Admin", organization_id: user.organization_id})

    name = "Contact Test Name New"
    phone = "1-415-555-1212 New"

    result =
      auth_query_gql_by(:update, user,
        variables: %{"id" => contact.id, "input" => %{"name" => name, "phone" => phone}}
      )

    assert {:ok, query_data} = result

    new_name = get_in(query_data, [:data, "updateContact", "contact", "name"])
    assert new_name == name

    # create a temp contact with a new phone number
    _ =
      auth_query_gql_by(:create, user,
        variables: %{"input" => %{"name" => "Yet another name", "phone" => phone <> " New"}}
      )

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => contact.id,
          "input" => %{"name" => name, "phone" => phone <> " New"}
        }
      )

    # ensure we cannot update an existing contact with the same phone
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateContact", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "delete a contact", %{user: user} do
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

  test "get contact location", %{user: user} do
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
        latitude: Faker.Address.latitude()
      })

    # get contact location
    result = auth_query_gql_by(:contact_location, user, variables: %{"id" => contact.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "contactLocation", "longitude"]) == location.longitude
  end

  test "search contacts field returns list of contacts with options set", %{user: user} do
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
    # adelle, hence checking the first two contacts
    assert get_in(contact_a, ["name"]) == "Adelle Cavin" or
    get_in(contact_b, ["name"]) == "Adelle Cavin"
  end

  test "search contacts field obeys group filters", %{user: user} do
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

  test "search contacts field obeys tag filters", %{user: user} do
    [ct1, _ct2, ct3] = Fixtures.contact_tags_fixture(%{organization_id: user.organization_id})

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
            "includeTags" => ["#{ct1.tag_id}", "#{ct3.tag_id}"],
            "includeGroups" => ["#{cg3.group_id}"]
          }
        }
      )

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "contacts"])) == 1
    assert get_in(query_data, [:data, "contacts", Access.at(0), "id"]) == "#{cg3.contact_id}"
  end
end
