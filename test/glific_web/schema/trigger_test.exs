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
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/triggers/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/triggers/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/triggers/update.gql")
  # load_gql(:delete, GlificWeb.Schema, "assets/gql/triggers/delete.gql")

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
    valid_attrs_2 = Map.merge(attrs, %{start_at: ~U[2021-03-01 09:22:51Z]})
    tr_2 = Fixtures.trigger_fixture(valid_attrs_2)

    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "DESC"}})
    assert {:ok, query_data} = result
    triggers = get_in(query_data, [:data, "triggers"])
    assert length(triggers) > 0
    [trigger | _] = triggers
    assert String.to_integer(trigger["flow"]["id"]) == tr_2.flow_id
  end

  test "triggers field should return following limit and offset", %{staff: user} = attrs do
    _tr_1 = Fixtures.trigger_fixture(attrs)
    valid_attrs_2 = Map.merge(attrs, %{start_at: ~U[2021-03-01 09:22:51Z]})
    _tr_2 = Fixtures.trigger_fixture(valid_attrs_2)

    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "triggers"])) == 1

    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1, "offset" => 1}})

    assert {:ok, query_data} = result

    triggers = get_in(query_data, [:data, "triggers"])
    assert length(triggers) == 1
  end

  test "triggers field returns list of triggers in various filters",
       %{staff: user} = attrs do
    _tr_1 = Fixtures.trigger_fixture(attrs)
    valid_attrs_2 = Map.merge(attrs, %{start_at: ~U[2021-03-01 09:22:51Z]})
    tr_2 = Fixtures.trigger_fixture(valid_attrs_2)

    result = auth_query_gql_by(:list, user, variables: %{"flow" => %{"name" => "help"}})
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

  test "triggers id returns one triggers or nil", %{staff: user} = attrs do
    trigger = Fixtures.trigger_fixture(attrs)
    result = auth_query_gql_by(:by_id, user, variables: %{"id" => trigger.id})
    assert {:ok, query_data} = result

    flow_id = get_in(query_data, [:data, "trigger", "trigger", "flow", "id"])
    assert Integer.to_string(trigger.flow_id) == flow_id

    end_date = get_in(query_data, [:data, "trigger", "trigger", "end_date"])
    assert end_date == Date.to_string(trigger.end_date)

  end

  test "create a trigger and test possible scenarios and errors", %{manager: user} = attrs do

    [flow | _tail] = Glific.Flows.list_flows(%{organization_id: attrs.organization_id})

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "days" =>  1,
            "flowId" => flow.id,
            "groupId" => 1,
            "startDate" => "2020-12-30",
            "startTime" => "13:15:19",
            "endDate" => "2020-12-29T13:15:19Z",
            "isActive" => false,
            "isRepeating" => false
          }
        }
      )

    assert {:ok, query_data} = result

    flow_id = get_in(query_data, [:data, "createTrigger", "trigger", "flow", "id"])
    assert flow_id == Integer.to_string(flow.id)

  end
end
