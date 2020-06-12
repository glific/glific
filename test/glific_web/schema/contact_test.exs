defmodule GlificWeb.Schema.Query.ContactTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  setup do
    Glific.Seeds.seed_contacts()
    :ok
  end

  load_gql(:list, GlificWeb.Schema, "assets/gql/contacts/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/contacts/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/contacts/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/contacts/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/contacts/delete.gql")
  load_gql(:search, GlificWeb.Schema, "assets/gql/contacts/search.gql")

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
    {:ok, contact} = Glific.Repo.fetch_by(Glific.Contacts.Contact, %{name: "Default Sender"})

    result = query_gql_by(:delete, variables: %{"id" => contact.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteContact", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteContact", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "search for contacts" do
    {:ok, sender} = Glific.Repo.fetch_by(Glific.Contacts.Contact, %{name: "Default Sender"})
    {:ok, receiver} = Glific.Repo.fetch_by(Glific.Contacts.Contact, %{name: "Default receiver"})

    sender_id = to_string(sender.id)
    receiver_id = to_string(receiver.id)

    result = query_gql_by(:search, variables: %{"term" => "Default Sender"})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "search", Access.at(0), "id"]) == sender_id

    result = query_gql_by(:search, variables: %{"term" => "Default receiver"})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "search", Access.at(0), "id"]) == receiver_id

    result = query_gql_by(:search, variables: %{"term" => "Default"})
    assert {:ok, query_data} = result
    id_1 = get_in(query_data, [:data, "search", Access.at(0), "id"])
    id_2 = get_in(query_data, [:data, "search", Access.at(1), "id"])

    assert (id_1 == sender_id and id_2 == receiver_id) or
             (id_2 == sender_id and id_1 == receiver_id)

    result =
      query_gql_by(:search,
        variables: %{"term" => "This term is highly unlikely to occur superfragerlicious"}
      )

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "search"]) == []
  end
end
