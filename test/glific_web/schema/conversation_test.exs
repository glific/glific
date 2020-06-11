defmodule GlificWeb.Schema.Query.ConversationTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  setup do
    Glific.Seeds.seed_contacts()
    Glific.Seeds.seed_messages()
    :ok
  end

  load_gql(:list, GlificWeb.Schema, "assets/gql/conversations/list.gql")

  test "conversations always returns a few threads" do
    {:ok, result} = query_gql_by(:list, variables: %{"nc" => 1, "sc" => 3})
    assert get_in(result, [:data, "conversations"]) |> length >= 1

    contact_id = get_in(result, [:data, "conversations", Access.at(0), "contact", "id"])

    {:ok, result} = query_gql_by(:list, variables: %{"nc" => 1, "sc" => 1, "filter" => %{"id" => contact_id}})
    assert get_in(result, [:data, "conversations"]) |> length == 1
  end
end
