defmodule GlificWeb.Schema.TriggerTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.Fixtures

  load_gql(:list, GlificWeb.Schema, "assets/gql/triggers/list.gql")

  test "triggers field returns list of triggers", %{staff: user} = attrs do
    wl = Fixtures.trigger_fixture(attrs)

    result = auth_query_gql_by(:list, user, variables: %{})
    assert {:ok, query_data} = result
    triggers = get_in(query_data, [:data, "triggers"])
    assert length(triggers) > 0
    [trigger | _] = triggers
    assert String.to_integer(trigger["flow"]["id"]) == wl.flow_id
  end

end
