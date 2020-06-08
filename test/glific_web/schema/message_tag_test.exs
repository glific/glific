defmodule GlificWeb.Schema.Query.MessageTagTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  setup do
    lang = Glific.Seeds.seed_language()
    Glific.Seeds.seed_tag(lang)
    Glific.Seeds.seed_contacts()
    Glific.Seeds.seed_messages()
    :ok
  end

  load_gql(:by_id, GlificWeb.Schema, "assets/gql/message_tags/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/message_tags/create.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/message_tags/delete.gql")

  test "message tag id returns one message tag or nil" do
    label = "This is for testing"
    {:ok, tag} = Glific.Repo.fetch_by(Glific.Tags.Tag, %{label: label})
    body = "default message body"
    {:ok, message} = Glific.Repo.fetch_by(Glific.Messages.Message, %{body: body})

    {:ok, query_data} =
      query_gql_by(:create,
        variables: %{"input" => %{"message_id" => message.id, "tag_id" => tag.id}}
      )

    message_tag_id = get_in(query_data, [:data, "createMessageTag", "message_tag", "id"])

    result = query_gql_by(:by_id, variables: %{"id" => message_tag_id})
    assert {:ok, query_data} = result

    message_id = get_in(query_data, [:data, "messageTag", "message_tag", "id"])
    assert message_id == message_id
  end

  test "create a message tag and test possible scenarios and errors" do
    label = "This is for testing"
    {:ok, tag} = Glific.Repo.fetch_by(Glific.Tags.Tag, %{label: label})
    body = "default message body"
    {:ok, message} = Glific.Repo.fetch_by(Glific.Messages.Message, %{body: body})

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"message_id" => message.id, "tag_id" => tag.id}}
      )

    assert {:ok, query_data} = result

    message_tag = get_in(query_data, [:data, "createMessageTag", "message_tag"])
    assert message_tag["message"]["id"] |> String.to_integer() == message.id
    assert message_tag["tag"]["id"] |> String.to_integer() == tag.id
  end

  test "delete a message tag" do
    label = "This is for testing"
    {:ok, tag} = Glific.Repo.fetch_by(Glific.Tags.Tag, %{label: label})
    body = "default message body"
    {:ok, message} = Glific.Repo.fetch_by(Glific.Messages.Message, %{body: body})

    {:ok, query_data} =
      query_gql_by(:create,
        variables: %{"input" => %{"message_id" => message.id, "tag_id" => tag.id}}
      )

    message_tag_id = get_in(query_data, [:data, "createMessageTag", "message_tag", "id"])

    result = query_gql_by(:delete, variables: %{"id" => message_tag_id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "deleteMessageTag", "errors"]) == nil
  end
end
