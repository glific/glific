defmodule GlificWeb.Schema.MessageTagsTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.Tags

  setup do
    default_provider = Glific.SeedsDev.seed_providers()
    Glific.SeedsDev.seed_organizations(default_provider)
    Glific.SeedsDev.seed_tag()
    Glific.SeedsDev.seed_contacts()
    Glific.SeedsDev.seed_messages()
    :ok
  end

  load_gql(:create, GlificWeb.Schema, "assets/gql/message_tags/create.gql")

  test "create a message tag and test possible scenarios and errors" do
    tags_map = Tags.status_map()
    body = "Default message body"
    {:ok, message} = Glific.Repo.fetch_by(Glific.Messages.Message, %{body: body})

    result =
      query_gql_by(:create,
        variables: %{
          "input" => %{
            "message_id" => message.id,
            "tags_id" => Map.values(tags_map)
          }
        }
      )

    assert {:ok, query_data} = result
    message_tags = get_in(query_data, [:data, "createMessageTags", "messageTags"])
    assert length(message_tags) == length(Map.values(tags_map))

    # add a known tag id not there in the DB (like a negative number?)
    result =
      query_gql_by(:create,
        variables: %{
          "input" => %{
            "message_id" => message.id,
            "tags_id" => Map.values(tags_map) ++ ["-1"]
          }
        }
      )

    assert {:ok, query_data} = result
    message_tags = get_in(query_data, [:data, "createMessageTags", "messageTags"])
    assert length(message_tags) == length(Map.values(tags_map))

    result =
      query_gql_by(:create,
        variables: %{
          "input" => %{
            "message_id" => message.id,
            "tags_id" => ["-1"]
          }
        }
      )

    assert {:ok, query_data} = result
    message_tags = get_in(query_data, [:data, "createMessageTags", "messageTags"])
    assert message_tags == []
  end
end
