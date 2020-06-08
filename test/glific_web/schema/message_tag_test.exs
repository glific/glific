defmodule GlificWeb.Schema.Query.MessageTagTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  setup do
    lang = Glific.Seeds.seed_language()
    Glific.Seeds.seed_tag(lang)
    Glific.Seeds.seed_contacts()
    Glific.Seeds.seed_messages()
    :ok
  end

  load_gql(:create, GlificWeb.Schema, "assets/gql/tags/create.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/tags/delete.gql")

  test "create a message tag and test possible scenarios and errors" do
    label = "This is for testing"
    {:ok, tag} = Glific.Repo.fetch_by(Glific.Tags.Tag, %{label: label})
    body = "default message body"
    {:ok, message} = Glific.Repo.fetch_by(Glific.Messages.Message, %{body: body})

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"messageId" => message.id, "tagId" => tag.id}}
      )

    assert {:ok, query_data} = result
    message_id = get_in(query_data, [:data, "createMessageTag", "message_id", "tag_id"])
    assert message_id == message.id
  end

end
