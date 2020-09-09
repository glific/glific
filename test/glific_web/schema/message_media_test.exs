defmodule GlificWeb.Schema.MessageMediaTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Messages.MessageMedia,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    SeedsDev.seed_messages_media()
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/messages_media/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/messages_media/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/messages_media/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/messages_media/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/messages_media/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/messages_media/delete.gql")

  test "messages media field returns list of messages", %{user: user} do
    result = auth_query_gql_by(:list, user)
    assert {:ok, query_data} = result

    messages_media = get_in(query_data, [:data, "messagesMedia"])
    assert length(messages_media) > 0

    [message_media | _] = messages_media
    assert get_in(message_media, ["caption"]) == "default caption"
  end

  test "messages media field obeys limit and offset", %{user: user} do
    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "messagesMedia"])) == 1

    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 3, "offset" => 1}})

    assert {:ok, query_data} = result

    messages_media = get_in(query_data, [:data, "messagesMedia"])
    assert length(messages_media) == 3

    # lets make sure we dont get Test as a message media caption
    assert get_in(messages_media, [Access.at(0), "caption"]) != "Test"
  end

  test "count returns the number of messages media", %{user: user} do
    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countMessagesMedia"]) == 4
  end

  test "message media id returns one message media or nil", %{user: user} do
    caption = "default caption"
    {:ok, message_media} = Repo.fetch_by(MessageMedia, %{caption: caption})

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => message_media.id})
    assert {:ok, query_data} = result

    message_caption = get_in(query_data, [:data, "messageMedia", "messageMedia", "caption"])
    assert message_caption == caption

    assert {:ok, query_data} = auth_query_gql_by(:by_id, user, variables: %{"id" => 123_456})

    assert "Resource not found" =
             get_in(query_data, [:data, "messageMedia", "errors", Access.at(0), "message"])
  end

  test "create a message media and test possible scenarios and errors", %{user: user} do
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "caption" => "My caption",
            "sourceUrl" =>
              "https://www.buildquickbots.com/whatsapp/media/sample/jpg/sample01.jpg",
            "thumbnail" =>
              "https://www.buildquickbots.com/whatsapp/media/sample/jpg/sample01.jpg",
            "url" => "https://www.buildquickbots.com/whatsapp/media/sample/jpg/sample01.jpg"
          }
        }
      )

    assert {:ok, query_data} = result

    assert "My caption" =
             get_in(query_data, [:data, "createMessageMedia", "messageMedia", "caption"])

    # create message without required atributes
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "caption" => "My caption",
            "sourceUrl" =>
              "https://www.buildquickbots.com/whatsapp/media/sample/jpg/sample01.jpg",
            "thumbnail" => "https://www.buildquickbots.com/whatsapp/media/sample/jpg/sample01.jpg"
          }
        }
      )

    assert {:ok, query_data} = result

    assert "can't be blank" =
             get_in(query_data, [:data, "createMessageMedia", "errors", Access.at(0), "message"])
  end

  test "update a message media and test possible scenarios and errors", %{user: user} do
    caption = "default caption"
    {:ok, message_media} = Repo.fetch_by(MessageMedia, %{caption: caption})

    result =
      auth_query_gql_by(:update, user,
        variables: %{"id" => message_media.id, "input" => %{"caption" => "Updated caption"}}
      )

    assert {:ok, query_data} = result

    assert "Updated caption" =
             get_in(query_data, [:data, "updateMessageMedia", "messageMedia", "caption"])

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => message_media.id,
          "input" => %{"url" => ""}
        }
      )

    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "updateMessageMedia", "errors", Access.at(0), "message"])
    assert message == "can't be blank"
  end

  test "delete a message media", %{user: user} do
    caption = "default caption"
    {:ok, message_media} = Repo.fetch_by(MessageMedia, %{caption: caption})

    result = auth_query_gql_by(:delete, user, variables: %{"id" => message_media.id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "deleteMessageMedia", "errors"]) == nil

    result = auth_query_gql_by(:delete, user, variables: %{"id" => message_media.id})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteMessageMedia", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end
end
