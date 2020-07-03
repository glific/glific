defmodule GlificWeb.Schema.MessageTagsTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.Tags

  setup do
    Glific.SeedsDev.seed_tag()
    Glific.SeedsDev.seed_contacts()
    Glific.SeedsDev.seed_messages()
    :ok
  end

  load_gql(:update, GlificWeb.Schema, "assets/gql/message_tags/update.gql")

  test "update a message tag with add tags" do
    tags_map = Tags.status_map()
    body = "Default message body"
    {:ok, message} = Glific.Repo.fetch_by(Glific.Messages.Message, %{body: body})

    result =
      query_gql_by(:update,
        variables: %{
          "input" => %{
            "message_id" => message.id,
            "add_tag_ids" => Map.values(tags_map),
            "delete_tag_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    message_tags = get_in(query_data, [:data, "updateMessageTags", "messageTags"])
    assert length(message_tags) == length(Map.values(tags_map))

    # add a known tag id not there in the DB (like a negative number?)
    result =
      query_gql_by(:update,
        variables: %{
          "input" => %{
            "message_id" => message.id,
            "add_tag_ids" => Map.values(tags_map) ++ ["-1"],
            "delete_tag_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    message_tags = get_in(query_data, [:data, "updateMessageTags", "messageTags"])
    assert length(message_tags) == length(Map.values(tags_map))

    result =
      query_gql_by(:update,
        variables: %{
          "input" => %{
            "message_id" => message.id,
            "add_tag_ids" => ["-1"],
            "delete_tag_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    message_tags = get_in(query_data, [:data, "updateMessageTags", "messageTags"])
    assert message_tags == []
  end

  test "update a message tag with add and delete tags" do
    tags_map = Tags.status_map()
    body = "Default message body"
    {:ok, message} = Glific.Repo.fetch_by(Glific.Messages.Message, %{body: body})

    # add some tags, test bad deletion value
    result =
      query_gql_by(:update,
        variables: %{
          "input" => %{
            "message_id" => message.id,
            "add_tag_ids" => Map.values(tags_map),
            "delete_tag_ids" => [-1]
          }
        }
      )

    assert {:ok, query_data} = result
    message_tags = get_in(query_data, [:data, "updateMessageTags", "messageTags"])
    assert length(message_tags) == length(Map.values(tags_map))
    assert 0 == get_in(query_data, [:data, "updateMessageTags", "numberDeleted"])

    # now delete all the added tags
    result =
      query_gql_by(:update,
        variables: %{
          "input" => %{
            "message_id" => message.id,
            "add_tag_ids" => [],
            "delete_tag_ids" => Map.values(tags_map)
          }
        }
      )

    assert {:ok, query_data} = result
    message_tags = get_in(query_data, [:data, "updateMessageTags", "messageTags"])
    assert Enum.empty?(message_tags)
  end
end
