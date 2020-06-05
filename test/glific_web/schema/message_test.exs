defmodule GlificWeb.Schema.Query.MessageTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  setup do
    Glific.Seeds.seed_messages()
    :ok
  end

  load_gql(:list, GlificWeb.Schema, "assets/gql/messages/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/messages/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/messages/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/messages/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/messages/delete.gql")

  test "messages field returns list of messages" do
    result = query_gql_by(:list)
    assert {:ok, query_data} = result

    tags = get_in(query_data, [:data, "tags"])
    assert length(tags) > 0

    [tag | _] = tags
    assert get_in(tag, ["label"]) == "Greeting"

    # lets ensure that the language field exists and has a valid id
    assert get_in(tag, ["language", "id"]) > 0
  end


end
