defmodule GlificWeb.Schema.MessageTest do
  alias Glific.{
    Contacts,
    Contacts.Contact,
    Messages,
    Messages.Message,
    Partners,
    Repo,
    Seeds.SeedsDev,
    Templates.SessionTemplate
  }

  use GlificWeb.ConnCase

  use Wormwood.GQLCase

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    :ok
  end

  load_gql(
    :create_and_send_message,
    GlificWeb.Schema,
    "assets/gql/messages/create_and_send_message.gql"
  )

  load_gql(
    :create_and_send_message_to_contacts,
    GlificWeb.Schema,
    "assets/gql/messages/create_and_send_message_to_contacts.gql"
  )

  load_gql(
    :send_hsm_message,
    GlificWeb.Schema,
    "assets/gql/messages/send_hsm_message.gql"
  )

  load_gql(:count, GlificWeb.Schema, "assets/gql/messages/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/messages/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/messages/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/messages/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/messages/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/messages/delete.gql")

  test "messages field returns list of messages" do
    result = query_gql_by(:list)
    assert {:ok, query_data} = result

    messages = get_in(query_data, [:data, "messages"])
    assert length(messages) > 0

    [message | _] = messages

    # lets ensure that the sender and receiver field exists and has a valid id
    assert get_in(message, ["sender", "id"]) > 0
    assert get_in(message, ["receiver", "id"]) > 0
  end

  test "messages field returns list of messages in various filters" do
    result = query_gql_by(:list, variables: %{"filter" => %{"body" => "Default message body"}})
    assert {:ok, query_data} = result

    messages = get_in(query_data, [:data, "messages"])
    assert length(messages) > 0
    [message | _] = messages
    assert get_in(message, ["body"]) == "Default message body"

    result = query_gql_by(:list, variables: %{"filter" => %{"receiver" => "Default receiver"}})
    assert {:ok, query_data} = result

    messages = get_in(query_data, [:data, "messages"])
    assert length(messages) > 0
    [message | _] = messages
    assert get_in(message, ["receiver", "name"]) == "Default receiver"

    result = query_gql_by(:list, variables: %{"filter" => %{"user" => "John"}})
    assert {:ok, query_data} = result

    messages = get_in(query_data, [:data, "messages"])
    assert messages == []
  end

  test "messages field returns list of messages in desc order" do
    result = query_gql_by(:list, variables: %{"opts" => %{"order" => "DESC"}})
    assert {:ok, query_data} = result

    messages = get_in(query_data, [:data, "messages"])
    assert length(messages) > 0

    [message | _] = messages

    assert get_in(message, ["body"]) == "ZZZ message body for order test"
  end

  test "messages field obeys limit and offset" do
    result = query_gql_by(:list, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})
    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "messages"])) == 1

    result = query_gql_by(:list, variables: %{"opts" => %{"limit" => 3, "offset" => 1}})
    assert {:ok, query_data} = result

    messages = get_in(query_data, [:data, "messages"])
    assert length(messages) == 3

    # lets make sure we dont get Test as a message
    assert get_in(messages, [Access.at(0), "body"]) != "Test"
    assert get_in(messages, [Access.at(1), "body"]) != "Test"
    assert get_in(messages, [Access.at(2), "body"]) != "Test"
  end

  test "count returns the number of messages" do
    {:ok, query_data} = query_gql_by(:count)
    assert get_in(query_data, [:data, "countMessages"]) > 5

    {:ok, query_data} =
      query_gql_by(:count,
        variables: %{"filter" => %{"body" => "This message should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countMessages"]) == 0

    {:ok, query_data} =
      query_gql_by(:count, variables: %{"filter" => %{"body" => "default message body"}})

    assert get_in(query_data, [:data, "countMessages"]) == 1
  end

  test "message id returns one message or nil" do
    body = "Default message body"
    {:ok, message} = Repo.fetch_by(Message, %{body: body})

    result = query_gql_by(:by_id, variables: %{"id" => message.id})
    assert {:ok, query_data} = result

    message_body = get_in(query_data, [:data, "message", "message", "body"])
    assert message_body == body

    result = query_gql_by(:by_id, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "message", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "create a message and test possible scenarios and errors" do
    [message | _] = Messages.list_messages()

    result =
      query_gql_by(:create,
        variables: %{
          "input" => %{
            "body" => "Message body",
            "flow" => "OUTBOUND",
            "receiverId" => message.receiver_id,
            "senderId" => message.sender_id,
            "type" => "TEXT"
          }
        }
      )

    assert {:ok, query_data} = result
    assert "Message body" = get_in(query_data, [:data, "createMessage", "message", "body"])

    # create message without required atributes
    result =
      query_gql_by(:create,
        variables: %{
          "input" => %{
            "body" => "Message body",
            "flow" => "OUTBOUND",
            "type" => "TEXT"
          }
        }
      )

    assert {:ok, query_data} = result

    assert "can't be blank" =
             get_in(query_data, [:data, "createMessage", "errors", Access.at(0), "message"])
  end

  test "update a message and test possible scenarios and errors" do
    body = "Default message body"
    {:ok, message} = Repo.fetch_by(Message, %{body: body})

    result =
      query_gql_by(:update,
        variables: %{"id" => message.id, "input" => %{"body" => "Updated body"}}
      )

    assert {:ok, query_data} = result
    assert "Updated body" = get_in(query_data, [:data, "updateMessage", "message", "body"])

    result =
      query_gql_by(:update,
        variables: %{
          "id" => message.id,
          "input" => %{"sender_id" => ""}
        }
      )

    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "updateMessage", "errors", Access.at(0), "message"])
    assert message == "can't be blank"
  end

  test "delete a message" do
    body = "Default message body"
    {:ok, message} = Repo.fetch_by(Message, %{body: body})

    result = query_gql_by(:delete, variables: %{"id" => message.id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "deleteMessage", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => message.id})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteMessage", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "send message to multiple contacts" do
    name = "Margarita Quinteros"
    {:ok, contact1} = Repo.fetch_by(Contact, %{name: name})

    name = "Adelle Cavin"
    {:ok, contact2} = Repo.fetch_by(Contact, %{name: name})

    result =
      query_gql_by(:create_and_send_message_to_contacts,
        variables: %{
          "input" => %{
            "body" => "Message body",
            "flow" => "OUTBOUND",
            "type" => "TEXT",
            "sender_id" => Partners.organization_contact_id()
          },
          "contact_ids" => [contact1.id, contact2.id]
        }
      )

    assert {:ok, query_data} = result
    messages = get_in(query_data, [:data, "createAndSendMessageToContacts"])
    assert length(messages) == 2
    [message | _] = messages
    assert message["receiver"]["id"] == contact1.id || contact2.id
  end

  test "send hsm message to an opted in contact" do
    name = "Default receiver"
    {:ok, contact} = Repo.fetch_by(Contact, %{name: name})

    Contacts.update_contact(contact, %{optin_time: DateTime.utc_now()})

    label = "OTP Message"
    {:ok, hsm_template} = Repo.fetch_by(SessionTemplate, %{label: label})

    parameters = ["param1", "param2", "param3"]

    result =
      query_gql_by(:send_hsm_message,
        variables: %{
          "id" => hsm_template.id,
          "receiver_id" => contact.id,
          "parameters" => parameters
        }
      )

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "sendHsmMessage", "errors"]) == nil
    assert get_in(query_data, [:data, "sendHsmMessage", "message", "is_hsm"]) == true
  end

  test "create and send a message to valid contact" do
    [contact | _tail] = Contacts.list_contacts()
    Contacts.contact_opted_in(contact.phone, DateTime.utc_now())
    {:ok, contact} = Contacts.update_contact(contact, %{last_message_at: DateTime.utc_now()})

    result =
      query_gql_by(:create_and_send_message,
        variables: %{
          "input" => %{
            "body" => "Message body",
            "flow" => "OUTBOUND",
            "receiverId" => contact.id,
            "senderId" => Partners.organization_contact_id(),
            "type" => "TEXT"
          }
        }
      )

    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "createAndSendMessage", "message"])
    assert message["body"] == "Message body"
  end

  test "create and send a message should parse the message body" do
    [contact | _tail] = Contacts.list_contacts()
    Contacts.contact_opted_in(contact.phone, DateTime.utc_now())
    {:ok, contact} = Contacts.update_contact(contact, %{last_message_at: DateTime.utc_now()})

    result =
      query_gql_by(:create_and_send_message,
        variables: %{
          "input" => %{
            "body" => "A message for @contact.name",
            "flow" => "OUTBOUND",
            "receiverId" => contact.id,
            "senderId" => Partners.organization_contact_id(),
            "type" => "TEXT"
          }
        }
      )

    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "createAndSendMessage", "message"])
    assert message["body"] == "A message for " <> contact.name
  end

  test "create and send a message to in valid contact will not create a message" do
    [contact | _tail] = Contacts.list_contacts()
    Contacts.contact_opted_out(contact.phone, DateTime.utc_now())
    message_body = Faker.Lorem.sentence()

    result =
      query_gql_by(:create_and_send_message,
        variables: %{
          "input" => %{
            "body" => message_body,
            "flow" => "OUTBOUND",
            "receiverId" => contact.id,
            "senderId" => Partners.organization_contact_id(),
            "type" => "TEXT"
          }
        }
      )

    assert {:error, "Resource not found"} ==
             Repo.fetch_by(Message, %{contact_id: contact.id, body: message_body})

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "createAndSendMessage"]) == nil

    message = get_in(query_data, [:errors, Access.at(0)])[:message]
    assert message == "Cannot send the message to the contact."
  end
end
