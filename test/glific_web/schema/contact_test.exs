defmodule GlificWeb.Schema.ContactTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  setup do
    lang = Glific.Seeds.seed_language()
    default_provider = Glific.Seeds.seed_providers()
    Glific.Seeds.seed_organizations(default_provider, lang)
    Glific.Seeds.seed_contacts()
    Glific.Seeds.seed_messages()
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/contacts/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/contacts/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/contacts/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/contacts/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/contacts/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/contacts/delete.gql")

  test "contacts field returns list of contacts" do
    result = query_gql_by(:list)
    assert {:ok, query_data} = result

    contacts = get_in(query_data, [:data, "contacts"])
    assert length(contacts) > 0

    res =
      contacts |> get_in([Access.all(), "name"]) |> Enum.find(fn x -> x == "Default Sender" end)

    assert res == "Default Sender"
  end

  test "contacts field returns list of contacts in asc order" do
    result = query_gql_by(:list, variables: %{"opts" => %{"order" => "ASC"}})
    assert {:ok, query_data} = result

    contacts = get_in(query_data, [:data, "contacts"])
    assert length(contacts) > 0

    [contact | _] = contacts

    assert get_in(contact, ["name"]) == "Adelle Cavin"
  end

  test "contacts field obeys limit and offset" do
    result = query_gql_by(:list, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})
    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "contacts"])) == 1

    result = query_gql_by(:list, variables: %{"opts" => %{"limit" => 3, "offset" => 1}})
    assert {:ok, query_data} = result

    contacts = get_in(query_data, [:data, "contacts"])
    assert length(contacts) == 3

    # lets make sure we dont get Test as a contact
    assert get_in(contacts, [Access.at(0), "name"]) != "Test"
    assert get_in(contacts, [Access.at(1), "name"]) != "Test"
    assert get_in(contacts, [Access.at(2), "name"]) != "Test"
  end

  test "count returns the number of contacts" do
    {:ok, query_data} = query_gql_by(:count)
    assert get_in(query_data, [:data, "countContacts"]) == 6

    {:ok, query_data} =
      query_gql_by(:count,
        variables: %{"filter" => %{"name" => "This contact should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countContacts"]) == 0

    {:ok, query_data} =
      query_gql_by(:count, variables: %{"filter" => %{"name" => "Default Sender"}})

    assert get_in(query_data, [:data, "countContacts"]) == 1
  end

  test "contact id returns one contact or nil" do
    name = "Default Sender"
    {:ok, contact} = Glific.Repo.fetch_by(Glific.Contacts.Contact, %{name: name})

    result = query_gql_by(:by_id, variables: %{"id" => contact.id})
    assert {:ok, query_data} = result

    contact = get_in(query_data, [:data, "contact", "contact", "name"])
    assert contact == name

    result = query_gql_by(:by_id, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "contact", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "create a contact and test possible scenarios and errors" do
    name = "Contact Test Name Uno"
    phone = "1-415-555-1212"

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"name" => name, "phone" => phone}}
      )

    assert {:ok, query_data} = result
    contact = get_in(query_data, [:data, "createContact", "contact"])
    assert Map.get(contact, "name") == name
    assert Map.get(contact, "phone") == phone

    # try creating the same contact twice
    _ =
      query_gql_by(:create,
        variables: %{"input" => %{"name" => name, "phone" => phone}}
      )

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"name" => name, "phone" => phone}}
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "createContact", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "update a contact and test possible scenarios and errors" do
    {:ok, contact} = Glific.Repo.fetch_by(Glific.Contacts.Contact, %{name: "Default Sender"})

    name = "Contact Test Name New"
    phone = "1-415-555-1212 New"

    result =
      query_gql_by(:update,
        variables: %{"id" => contact.id, "input" => %{"name" => name, "phone" => phone}}
      )

    assert {:ok, query_data} = result

    new_name = get_in(query_data, [:data, "updateContact", "contact", "name"])
    assert new_name == name

    # create a temp contact with a new phone number
    _ =
      query_gql_by(:create,
        variables: %{"input" => %{"name" => "Yet another name", "phone" => phone <> " New"}}
      )

    result =
      query_gql_by(:update,
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

  test "delete a contact" do
    # Delete a random contact
    {:ok, contact} = Glific.Repo.fetch_by(Glific.Contacts.Contact, %{name: "Chrissy Cron"})

    result = query_gql_by(:delete, variables: %{"id" => contact.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteContact", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteContact", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end
end
