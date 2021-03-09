defmodule GlificWeb.Schema.TriggerTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Seeds.SeedsDev,
    Triggers.Trigger
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_flows(organization)
    SeedsDev.seed_groups(organization)
    :ok
  end

  load_gql(:list, GlificWeb.Schema, "assets/gql/triggers/list.gql")
  load_gql(:count, GlificWeb.Schema, "assets/gql/triggers/count.gql")

  test "triggers field returns list of triggers", %{staff: user} = attrs do
    tr = Fixtures.trigger_fixture(attrs)

    result = auth_query_gql_by(:list, user, variables: %{})
    assert {:ok, query_data} = result
    triggers = get_in(query_data, [:data, "triggers"])
    assert length(triggers) > 0
    [trigger | _] = triggers
    assert String.to_integer(trigger["flow"]["id"]) == tr.flow_id
  end

  test "triggers field returns list of triggers in desc order", %{staff: user} = attrs do
    _tr_1 = Fixtures.trigger_fixture(attrs)
    flow = Fixtures.flow_fixture(attrs)
    valid_attrs_2 = Map.merge(attrs, %{start_at: ~U[2021-03-11 09:22:51Z], flow_id: flow.id})
    tr_2 = Fixtures.trigger_fixture(valid_attrs_2)

    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "DESC"}})
    assert {:ok, query_data} = result
    triggers = get_in(query_data, [:data, "triggers"])
    assert length(triggers) > 0
    [trigger | _] = triggers
    assert String.to_integer(trigger["flow"]["id"]) == tr_2.flow_id
  end

  test "count_triggers/0 returns count of all trigger logs", attrs do
    logs_count = Trigger.count_triggers(%{filter: attrs})

    Fixtures.trigger_fixture(attrs)
    assert Trigger.count_triggers(%{filter: attrs}) == logs_count + 1
  end
end
