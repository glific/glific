defmodule GlificWeb.Schema.MessageTagTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  setup do
    default_provider = Glific.SeedsDev.seed_providers()
    Glific.SeedsDev.seed_organizations(default_provider)
    Glific.SeedsDev.seed_tag()
    Glific.SeedsDev.seed_contacts()
    Glific.SeedsDev.seed_messages()
    :ok
  end

  load_gql(:create, GlificWeb.Schema, "assets/gql/message_tag/create.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/message_tag/delete.gql")

  test "create a message tag and test possible scenarios and errors" do
    label = "This is for testing"
    {:ok, tag} = Glific.Repo.fetch_by(Glific.Tags.Tag, %{label: label})
    body = "Default message body"
    {:ok, message} = Glific.Repo.fetch_by(Glific.Messages.Message, %{body: body})

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"message_id" => message.id, "tag_id" => tag.id}}
      )

    assert {:ok, query_data} = result

    message_tag = get_in(query_data, [:data, "createMessageTag", "message_tag"])
    assert message_tag["message"]["id"] |> String.to_integer() == message.id
    assert message_tag["tag"]["id"] |> String.to_integer() == tag.id

    # try creating the same message tag twice
    # upserts come into play here and we dont return an error
    result =
      query_gql_by(:create,
        variables: %{"input" => %{"message_id" => message.id, "tag_id" => tag.id}}
      )

    assert {:ok, query_data} = result

    message_tag = get_in(query_data, [:data, "createMessageTag", "message_tag"])
    assert get_in(message_tag, ["message", "id"]) |> String.to_integer() == message.id
    assert get_in(message_tag, ["tag", "id"]) |> String.to_integer() == tag.id
  end

  test "delete a message tag" do
    label = "This is for testing"
    {:ok, tag} = Glific.Repo.fetch_by(Glific.Tags.Tag, %{label: label})
    body = "Default message body"
    {:ok, message} = Glific.Repo.fetch_by(Glific.Messages.Message, %{body: body})

    {:ok, query_data} =
      query_gql_by(:create,
        variables: %{
          "input" => %{"message_id" => to_string(message.id), "tag_id" => to_string(tag.id)}
        }
      )

    message_tag_id = get_in(query_data, [:data, "createMessageTag", "message_tag", "id"])

    result = query_gql_by(:delete, variables: %{"id" => message_tag_id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "deleteMessageTag", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => message_tag_id})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteMessageTag", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end
end
