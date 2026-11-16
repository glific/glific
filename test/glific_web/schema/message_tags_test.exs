defmodule GlificWeb.Schema.MessageTagsTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  import Ecto.Query

  alias Glific.{
    Fixtures,
    Messages.Message,
    Repo,
    Seeds.SeedsDev,
    Tags,
    Tags.MessageTag
  }

  setup do
    SeedsDev.seed_tag()
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    :ok
  end

  load_gql(:update, GlificWeb.Schema, "assets/gql/message_tags/update.gql")

  def tag_status_map(org_id) do
    Tags.status_map(%{organization_id: org_id})
  end

  test "update a message tag with add tags", %{staff: user} do
    tags_map = tag_status_map(user.organization_id)
    body = "Default message body"
    {:ok, message} = Repo.fetch_by(Message, %{body: body, organization_id: user.organization_id})

    result =
      auth_query_gql_by(:update, user,
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
      auth_query_gql_by(:update, user,
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
      auth_query_gql_by(:update, user,
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

  test "update a message tag with add and delete tags", %{staff: user} do
    tags_map = tag_status_map(user.organization_id)
    body = "Default message body"
    {:ok, message} = Repo.fetch_by(Message, %{body: body, organization_id: user.organization_id})

    # add some tags, test bad deletion value
    result =
      auth_query_gql_by(:update, user,
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
      auth_query_gql_by(:update, user,
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

  describe "cross-organization access" do
    setup %{staff: user} do
      other_organization =
        Fixtures.organization_fixture(%{shortcode: "other_organization_message_tags"})

      Repo.put_organization_id(other_organization.id)
      other_message = Fixtures.message_fixture(%{organization_id: other_organization.id})
      other_tag = Fixtures.tag_fixture(%{organization_id: other_organization.id})
      Repo.put_organization_id(user.organization_id)

      {:ok, message} =
        Repo.fetch_by(Message, %{
          body: "Default message body",
          organization_id: user.organization_id
        })

      %{message: message, other_message: other_message, other_tag: other_tag}
    end

    test "does not add another organization's tag", %{
      staff: user,
      message: message,
      other_tag: other_tag
    } do
      result =
        auth_query_gql_by(:update, user,
          variables: %{
            "input" => %{
              "message_id" => message.id,
              "add_tag_ids" => [other_tag.id],
              "delete_tag_ids" => []
            }
          }
        )

      assert {:ok, query_data} = result
      assert get_in(query_data, [:data, "updateMessageTags", "messageTags"]) == []
      refute Repo.exists?(MessageTag |> where(tag_id: ^other_tag.id), skip_organization_id: true)
    end

    test "rejects another organization's message", %{
      staff: user,
      other_message: other_message
    } do
      tag_ids = user.organization_id |> tag_status_map() |> Map.values()

      result =
        auth_query_gql_by(:update, user,
          variables: %{
            "input" => %{
              "message_id" => other_message.id,
              "add_tag_ids" => tag_ids,
              "delete_tag_ids" => []
            }
          }
        )

      assert {:ok, query_data} = result

      assert [%{"message" => message}] =
               get_in(query_data, [:data, "updateMessageTags", "errors"])

      assert message =~ "Resource not found"

      refute Repo.exists?(MessageTag |> where(message_id: ^other_message.id),
               skip_organization_id: true
             )
    end
  end
end
