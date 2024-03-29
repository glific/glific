defmodule GlificWeb.Schema.MessageTagTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Messages.Message,
    Repo,
    Seeds.SeedsDev,
    Tags.Tag
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_tag()
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    :ok
  end

  load_gql(:create, GlificWeb.Schema, "assets/gql/message_tag/create.gql")

  test "create a message tag and test possible scenarios and errors", %{manager: user} do
    label = "This is for testing"
    {:ok, tag} = Repo.fetch_by(Tag, %{label: label, organization_id: user.organization_id})
    body = "Default message body"
    {:ok, message} = Repo.fetch_by(Message, %{body: body, organization_id: user.organization_id})

    result =
      auth_query_gql_by(:create, user,
        variables: %{"input" => %{"message_id" => message.id, "tag_id" => tag.id}}
      )

    assert {:ok, query_data} = result

    message_tag = get_in(query_data, [:data, "createMessageTag", "message_tag"])
    assert message_tag["message"]["id"] |> String.to_integer() == message.id
    assert message_tag["tag"]["id"] |> String.to_integer() == tag.id

    # try creating the same message tag twice
    # upserts come into play here and we don't return an error
    result =
      auth_query_gql_by(:create, user,
        variables: %{"input" => %{"message_id" => message.id, "tag_id" => tag.id}}
      )

    assert {:ok, query_data} = result

    message_tag = get_in(query_data, [:data, "createMessageTag", "message_tag"])
    assert get_in(message_tag, ["message", "id"]) |> String.to_integer() == message.id
    assert get_in(message_tag, ["tag", "id"]) |> String.to_integer() == tag.id
  end
end
