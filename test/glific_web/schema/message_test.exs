defmodule GlificWeb.Schema.MessageTest do
  alias Glific.{
    Contacts,
    Fixtures,
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
    :create_and_send_message_to_group,
    GlificWeb.Schema,
    "assets/gql/messages/create_and_send_message_to_group.gql"
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
  load_gql(:clear, GlificWeb.Schema, "assets/gql/messages/clear.gql")

  test "messages field returns list of messages", %{staff: user} do
    result = auth_query_gql_by(:list, user)
    assert {:ok, query_data} = result

    messages = get_in(query_data, [:data, "messages"])
    assert length(messages) > 0

    [message | _] = messages

    # lets ensure that the sender and receiver field exists and has a valid id
    assert get_in(message, ["sender", "id"]) > 0
    assert get_in(message, ["receiver", "id"]) > 0
  end

  test "messages field returns list of messages in various filters", %{staff: user} do
    result =
      auth_query_gql_by(:list, user, variables: %{"filter" => %{"body" => "Default message body"}})

    assert {:ok, query_data} = result

    messages = get_in(query_data, [:data, "messages"])
    assert length(messages) > 0
    [message | _] = messages
    assert get_in(message, ["body"]) == "Default message body"

    result =
      auth_query_gql_by(:list, user, variables: %{"filter" => %{"receiver" => "Default receiver"}})

    assert {:ok, query_data} = result

    messages = get_in(query_data, [:data, "messages"])
    assert length(messages) > 0
    [message | _] = messages
    assert get_in(message, ["receiver", "name"]) == "Default receiver"

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"user" => "John"}})
    assert {:ok, query_data} = result

    messages = get_in(query_data, [:data, "messages"])
    assert messages == []
  end

  test "messages field returns list of messages in desc order", %{staff: user} do
    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "DESC"}})
    assert {:ok, query_data} = result

    messages = get_in(query_data, [:data, "messages"])
    assert length(messages) > 0

    [message | _] = messages

    assert get_in(message, ["body"]) == "ZZZ message body for order test"
  end

  test "messages field obeys limit and offset", %{staff: user} do
    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "messages"])) == 1

    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 3, "offset" => 1}})

    assert {:ok, query_data} = result

    messages = get_in(query_data, [:data, "messages"])
    assert length(messages) == 3

    # lets make sure we dont get Test as a message
    assert get_in(messages, [Access.at(0), "body"]) != "Test"
    assert get_in(messages, [Access.at(1), "body"]) != "Test"
    assert get_in(messages, [Access.at(2), "body"]) != "Test"
  end

  test "count returns the number of messages", %{staff: user} do
    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countMessages"]) > 5

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"body" => "This message should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countMessages"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"body" => "default message body"}}
      )

    assert get_in(query_data, [:data, "countMessages"]) == 1
  end

  test "message id returns one message or nil", %{staff: user} do
    body = "Default message body"
    {:ok, message} = Repo.fetch_by(Message, %{body: body, organization_id: user.organization_id})

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => message.id})
    assert {:ok, query_data} = result

    message_body = get_in(query_data, [:data, "message", "message", "body"])
    assert message_body == body

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "message", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "create a message and test possible scenarios and errors", %{staff: user} do
    message = Fixtures.message_fixture()

    result =
      auth_query_gql_by(:create, user,
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
      auth_query_gql_by(:create, user,
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

  test "update a message and test possible scenarios and errors", %{user: user} do
    body = "Default message body"
    {:ok, message} = Repo.fetch_by(Message, %{body: body, organization_id: user.organization_id})

    result =
      auth_query_gql_by(:update, user,
        variables: %{"id" => message.id, "input" => %{"body" => "Updated body"}}
      )

    assert {:ok, query_data} = result
    assert "Updated body" = get_in(query_data, [:data, "updateMessage", "message", "body"])

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => message.id,
          "input" => %{"sender_id" => ""}
        }
      )

    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "updateMessage", "errors", Access.at(0), "message"])
    assert message == "can't be blank"
  end

  test "delete a message", %{user: user} do
    body = "Default message body"
    {:ok, message} = Repo.fetch_by(Message, %{body: body, organization_id: user.organization_id})

    result = auth_query_gql_by(:delete, user, variables: %{"id" => message.id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "deleteMessage", "errors"]) == [nil]

    result = auth_query_gql_by(:delete, user, variables: %{"id" => message.id})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteMessage", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "clear messages of a contact", %{user: user} do
    body = "Default message body"
    {:ok, message} = Repo.fetch_by(Message, %{body: body, organization_id: user.organization_id})

    result = auth_query_gql_by(:clear, user, variables: %{"contactId" => message.contact_id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "clearMessages", "errors"]) == nil
    assert get_in(query_data, [:data, "clearMessages", "success"]) == true

    result = auth_query_gql_by(:clear, user, variables: %{"contactId" => 9_999_999})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "clearMessages", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "send message to a group", %{staff: user} = attrs do
    [cg1 | _] = Fixtures.group_contacts_fixture(attrs)

    result =
      auth_query_gql_by(:create_and_send_message_to_group, user,
        variables: %{
          "input" => %{
            "body" => "Message body",
            "flow" => "OUTBOUND",
            "type" => "TEXT",
            "sender_id" => Partners.organization_contact_id(user.organization_id)
          },
          "group_id" => cg1.group_id
        }
      )

    assert {:ok, query_data} = result
    contact_ids = get_in(query_data, [:data, "createAndSendMessageToGroup", "contactIds"])
    assert length(contact_ids) >= 2
  end

  test "send hsm message to an opted in contact", %{staff: user} do
    contact = Glific.Fixtures.contact_fixture()

    label = "OTP Message"

    {:ok, hsm_template} =
      Repo.fetch_by(SessionTemplate, %{label: label, organization_id: user.organization_id})

    parameters = ["param1", "param2", "param3"]

    result =
      auth_query_gql_by(:send_hsm_message, user,
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

  test "create and send a message to valid contact", %{staff: user} do
    contact = Fixtures.contact_fixture()

    {:ok, contact} =
      Contacts.update_contact(contact, %{
        last_message_at: DateTime.utc_now(),
        bsp_status: :session_and_hsm,
        optin_time: DateTime.utc_now()
      })

    result =
      auth_query_gql_by(:create_and_send_message, user,
        variables: %{
          "input" => %{
            "body" => "Message body",
            "flow" => "OUTBOUND",
            "receiverId" => contact.id,
            "senderId" => Partners.organization_contact_id(user.organization_id),
            "type" => "TEXT"
          }
        }
      )

    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "createAndSendMessage", "message"])
    assert message["body"] == "Message body"
  end

  test "create and send a message should parse the message body", %{staff: user} do
    contact = Fixtures.contact_fixture()

    {:ok, contact} =
      Contacts.update_contact(contact, %{
        last_message_at: DateTime.utc_now(),
        bsp_status: :session_and_hsm,
        optin_time: DateTime.utc_now()
      })

    result =
      auth_query_gql_by(:create_and_send_message, user,
        variables: %{
          "input" => %{
            "body" => "A message for @contact.name",
            "flow" => "OUTBOUND",
            "receiverId" => contact.id,
            "senderId" => Partners.organization_contact_id(user.organization_id),
            "type" => "TEXT"
          }
        }
      )

    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "createAndSendMessage", "message"])
    assert message["body"] == "A message for " <> contact.name
  end

  test "create and send a message to invalid contact will not create a message", %{staff: user} do
    contact = Fixtures.contact_fixture()
    Contacts.contact_opted_out(contact.phone, contact.organization_id, DateTime.utc_now())
    message_body = Faker.Lorem.sentence()

    result =
      auth_query_gql_by(:create_and_send_message, user,
        variables: %{
          "input" => %{
            "body" => message_body,
            "flow" => "OUTBOUND",
            "receiverId" => contact.id,
            "senderId" => Partners.organization_contact_id(user.organization_id),
            "type" => "TEXT"
          }
        }
      )

    assert {:error, ["Elixir.Glific.Messages.Message", "Resource not found"]} ==
             Repo.fetch_by(Message, %{
               contact_id: contact.id,
               body: message_body,
               organization_id: user.organization_id
             })

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "createAndSendMessage"]) == nil

    message = get_in(query_data, [:errors, Access.at(0)])[:message]
    assert message == "Cannot send the message to the contact."
  end
end
