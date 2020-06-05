defmodule GlificWeb.Schema.Query.MessageTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  setup do
    Glific.Seeds.seed_messages()
    :ok
  end

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
    assert get_in(message, ["body"]) == "default message body"

    # lets ensure that the sender and recipient field exists and has a valid id
    assert get_in(message, ["sender", "id"]) > 0
    assert get_in(message, ["recipient", "id"]) > 0
  end

  test "message id returns one message or nil" do
    body = "default message body"
    {:ok, message} = Glific.Repo.fetch_by(Glific.Messages.Message, %{body: body})

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
    body = "default message body"
    {:ok, message} = Glific.Repo.fetch_by(Glific.Messages.Message, %{body: body})

    result =
      query_gql_by(:create,
        variables: %{
          "input" => %{
            "body" => "Message body",
            "flow" => "OUTBOUND",
            "recipientId" => message.recipient_id,
            "senderId" => message.sender_id,
            "type" => "TEXT",
            "waStatus" => "DELIVERED"
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
            "type" => "TEXT",
            "waStatus" => "DELIVERED"
          }
        }
      )

    assert {:ok, query_data} = result

    assert "can't be blank" =
             get_in(query_data, [:data, "createMessage", "errors", Access.at(0), "message"])
  end

  test "update a message and test possible scenarios and errors" do
    body = "default message body"
    {:ok, message} = Glific.Repo.fetch_by(Glific.Messages.Message, %{body: body})

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
    body = "default message body"
    {:ok, message} = Glific.Repo.fetch_by(Glific.Messages.Message, %{body: body})

    result = query_gql_by(:delete, variables: %{"id" => message.id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "deleteMessage", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => message.id})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteMessage", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end
end
