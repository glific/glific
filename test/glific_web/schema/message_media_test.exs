defmodule GlificWeb.Schema.Query.MessageMediaTest do
  alias Glific.Messages.MessageMedia
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  setup do
    Glific.Seeds.seed_messages_media()
    :ok
  end

  load_gql(:list, GlificWeb.Schema, "assets/gql/messages_media/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/messages_media/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/messages_media/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/messages_media/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/messages_media/delete.gql")

  test "messages media field returns list of messages" do
    result = query_gql_by(:list)
    assert {:ok, query_data} = result

    messages_media = get_in(query_data, [:data, "messagesMedia"])
    assert length(messages_media) > 0

    [message_media | _] = messages_media
    assert get_in(message_media, ["caption"]) == "default caption"
  end

  test "message media id returns one message media or nil" do
    caption = "default caption"
    {:ok, message_media} = Glific.Repo.fetch_by(MessageMedia, %{caption: caption})

    result = query_gql_by(:by_id, variables: %{"id" => message_media.id})
    assert {:ok, query_data} = result

    message_caption = get_in(query_data, [:data, "messageMedia", "messageMedia", "caption"])
    assert message_caption == caption

    assert {:ok, query_data} = query_gql_by(:by_id, variables: %{"id" => 123_456})

    assert "Resource not found" =
             get_in(query_data, [:data, "messageMedia", "errors", Access.at(0), "message"])
  end

  test "create a message media and test possible scenarios and errors" do
    result =
      query_gql_by(:create,
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
      query_gql_by(:create,
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

  # @tag :pending
  test "update a message media and test possible scenarios and errors" do
    caption = "default caption"
    {:ok, message_media} = Glific.Repo.fetch_by(MessageMedia, %{caption: caption})

    result =
      query_gql_by(:update,
        variables: %{"id" => message_media.id, "input" => %{"caption" => "Updated caption"}}
      )

    assert {:ok, query_data} = result

    assert "Updated caption" =
             get_in(query_data, [:data, "updateMessageMedia", "messageMedia", "caption"])

    result =
      query_gql_by(:update,
        variables: %{
          "id" => message_media.id,
          "input" => %{"url" => ""}
        }
      )

    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "updateMessageMedia", "errors", Access.at(0), "message"])
    assert message == "can't be blank"
  end

  test "delete a message media" do
    caption = "default caption"
    {:ok, message_media} = Glific.Repo.fetch_by(MessageMedia, %{caption: caption})

    result = query_gql_by(:delete, variables: %{"id" => message_media.id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "deleteMessageMedia", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => message_media.id})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteMessageMedia", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end
end
