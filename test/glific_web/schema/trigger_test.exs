defmodule GlificWeb.Schema.TriggerTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Repo,
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
  load_gql(:delete, GlificWeb.Schema, "assets/gql/triggers/delete.gql")

  test "triggers field returns list of triggers", %{staff: user} = attrs do
    tr = Fixtures.trigger_fixture(attrs)

    result = auth_query_gql_by(:list, user, variables: %{})
    assert {:ok, query_data} = result
    triggers = get_in(query_data, [:data, "triggers"])
    assert length(triggers) > 0
    [trigger | _] = triggers
    assert String.to_integer(trigger["flow"]["id"]) == tr.flow_id
  end

  test "trigger field returns list of triggers in various filters", %{staff: user} = attrs do
    trigger =
      Fixtures.trigger_fixture(attrs)
      |> Repo.preload([:flow, :group])

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"name" => trigger.name}})
    assert {:ok, query_data} = result

    triggers = get_in(query_data, [:data, "triggers"])
    assert length(triggers) > 0

    result =
      auth_query_gql_by(:list, user, variables: %{"filter" => %{"flow" => trigger.flow.name}})

    assert {:ok, query_data} = result

    triggers = get_in(query_data, [:data, "triggers"])
    assert length(triggers) > 0

    result =
      auth_query_gql_by(:list, user, variables: %{"filter" => %{"group" => trigger.group.label}})

    assert {:ok, query_data} = result

    triggers = get_in(query_data, [:data, "triggers"])
    assert length(triggers) > 0
  end

  test "triggers field returns list of triggers in desc order", %{staff: user} = attrs do
    _tr_1 = Fixtures.trigger_fixture(attrs)
    time = Timex.shift(DateTime.utc_now(), days: 1)
    valid_attrs_2 = Map.merge(attrs, %{start_at: time})
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
    time = Timex.shift(DateTime.utc_now(), days: 1)
    valid_attrs_2 = Map.merge(attrs, %{start_at: time})
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
    time = Timex.shift(DateTime.utc_now(), days: 1)
    valid_attrs_2 = Map.merge(attrs, %{start_at: time})
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
    trigger =
      Fixtures.trigger_fixture(attrs)
      |> Repo.preload(:flow)

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => trigger.id})
    assert {:ok, query_data} = result

    flow_name = get_in(query_data, [:data, "trigger", "trigger", "flow", "name"])
    assert trigger.flow.name == flow_name

    {:ok, end_date} =
      get_in(query_data, [:data, "trigger", "trigger", "end_date"])
      |> Date.from_iso8601()

    assert end_date == trigger.end_date

    {:ok, start_date, _} =
      get_in(query_data, [:data, "trigger", "trigger", "start_at"])
      |> DateTime.from_iso8601()

    assert start_date == trigger.start_at
  end

  test "create a trigger and test possible scenarios and errors", %{manager: user} = attrs do
    [flow | _tail] = Glific.Flows.list_flows(%{organization_id: attrs.organization_id})
    [group | _tail] = Glific.Groups.list_groups(%{organization_id: attrs.organization_id})

    start_time = Timex.shift(DateTime.utc_now(), days: 1)
    {:ok, start_date} = Timex.format(start_time, "%Y-%m-%d", :strftime)
    end_time = Timex.shift(DateTime.utc_now(), days: 5)
    {:ok, end_date} = Timex.format(end_time, "%Y-%m-%d", :strftime)
    start_time = "13:15:19"

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "days" => 1,
            "flowId" => flow.id,
            "groupId" => group.id,
            "startDate" => start_date,
            "startTime" => start_time,
            "endDate" => end_date,
            "isActive" => false,
            "isRepeating" => false
          }
        }
      )

    assert {:ok, query_data} = result

    flow_name = get_in(query_data, [:data, "createTrigger", "trigger", "flow", "name"])
    assert flow_name == flow.name

    ## we are ignoring the enddate's time
    assert get_in(query_data, [:data, "createTrigger", "trigger", "end_date"]) == end_date

    ## start date should be converted into UTC
    {:ok, start_at, _} =
      get_in(query_data, [:data, "createTrigger", "trigger", "start_at"])
      |> DateTime.from_iso8601()

    {:ok, d} = Date.from_iso8601(start_date)
    {:ok, t} = Time.from_iso8601(start_time)
    time = DateTime.new!(d, t)

    assert time == start_at
  end

  test "create a trigger with time prior to current timestamp should raise an error",
       %{manager: user} = attrs do
    [flow | _tail] = Glific.Flows.list_flows(%{organization_id: attrs.organization_id})
    [group | _tail] = Glific.Groups.list_groups(%{organization_id: attrs.organization_id})

    start_time = Timex.shift(DateTime.utc_now(), days: -1)
    {:ok, start_date} = Timex.format(start_time, "%Y-%m-%d", :strftime)
    end_time = Timex.shift(DateTime.utc_now(), days: 5)
    {:ok, end_date} = Timex.format(end_time, "%Y-%m-%d", :strftime)
    start_time = "13:15:19"

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "flowId" => flow.id,
            "groupId" => group.id,
            "startDate" => start_date,
            "startTime" => start_time,
            "endDate" => end_date,
            "isActive" => false,
            "isRepeating" => false
          }
        }
      )

    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "createTrigger", "errors", Access.at(0), "message"])
    assert message =~ "Trigger start_at should always be greater than current time"
  end

  test "update a trigger and test possible scenarios and errors", %{manager: user} = attrs do
    trigger =
      Fixtures.trigger_fixture(attrs)
      |> Repo.preload(:flow)

    start_time = Timex.shift(DateTime.utc_now(), days: 1)
    {:ok, start_date} = Timex.format(start_time, "%Y-%m-%d", :strftime)
    start_time = "13:15:19"

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => trigger.id,
          "input" => %{
            "startDate" => start_date,
            "startTime" => start_time,
            "isActive" => true,
            "flowId" => trigger.flow_id
          }
        }
      )

    assert {:ok, query_data} = result
    flow_name = get_in(query_data, [:data, "updateTrigger", "trigger", "flow", "name"])

    assert flow_name == trigger.flow.name

    assert get_in(query_data, [:data, "updateTrigger", "trigger", "end_date"]) ==
             Date.to_string(trigger.end_date)
  end

  test "update a trigger with existing name and next_trigger_at", attrs do
    trigger = Fixtures.trigger_fixture(Map.merge(attrs, %{next_trigger_at: DateTime.utc_now()}))

    update_attrs = %{
      start_at: trigger.start_at,
      next_trigger_at: trigger.next_trigger_at,
      flow_id: trigger.flow_id,
      organization_id: trigger.organization_id,
      is_active: false,
      name: trigger.name
    }

    {:ok, updated_trigger} = Trigger.update_trigger(trigger, update_attrs)
    assert trigger.name == updated_trigger.name
    assert trigger.next_trigger_at == updated_trigger.next_trigger_at
  end

  test "delete a trigger", %{manager: user} = attrs do
    trigger =
      Fixtures.trigger_fixture(attrs)
      |> Repo.preload(:flow)

    result = auth_query_gql_by(:delete, user, variables: %{"id" => trigger.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteTrigger", "errors"]) == nil

    result = auth_query_gql_by(:delete, user, variables: %{"id" => trigger.id})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteTrigger", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end
end
