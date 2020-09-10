defmodule Glific.Flows.PeriodicTest do
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Flows.Periodic
  }

  def setup do
    :ok
  end

  test "compute time and its various permutions" do
    # get the beginning of a month
    {:ok, month} = Timex.parse("2020-08-01T00:00:00-08:00", "{ISO:Extended}")
    {:ok, any_day} = Timex.parse("2020-08-13T00:00:00-08:00", "{ISO:Extended}")
    {:ok, last_day} = Timex.parse("2020-08-31T00:00:00-08:00", "{ISO:Extended}")

    assert Periodic.compute_time(month, "monthly") == month
    assert Periodic.compute_time(any_day, "monthly") == month
    assert Periodic.compute_time(last_day, "monthly") == month

    {:ok, monday} = Timex.parse("2020-08-10T00:00:00-08:00", "{ISO:Extended}")
    {:ok, thursday} = Timex.parse("2020-08-13T00:00:00-08:00", "{ISO:Extended}")
    {:ok, sunday} = Timex.parse("2020-08-16T00:00:00-08:00", "{ISO:Extended}")
    assert Periodic.compute_time(monday, "weekly") == monday
    assert Periodic.compute_time(any_day, "weekly") == monday
    assert Periodic.compute_time(sunday, "weekly") == monday

    assert Periodic.compute_time(DateTime.add(monday, 125 * 6 * 60), "monday") == monday
    assert Periodic.compute_time(DateTime.add(monday, 125 * 6 * 60), "daily") == monday

    assert Periodic.compute_time(DateTime.add(thursday, 60 * 6 * 60), "monday") == thursday
    assert Periodic.compute_time(DateTime.add(thursday, 73 * 6 * 60), "daily") == thursday
  end

  test "map flow ids" do
    filled_map = %{flows: %{filled: true}}
    assert Periodic.map_flow_ids(filled_map) == filled_map

    filled_map = Periodic.map_flow_ids(%{organization_id: Fixtures.get_org_id()})
    assert filled_map.flows.filled == true

    # we know that outofoffice is a default seeded flow
    assert !is_nil(get_in(filled_map, [:flows, "outofoffice"]))
  end

  @tag :pending
  test "run flows and we know the outofoffice flow should get going", attrs do
    FunWithFlags.enable(:enable_out_of_office)
    FunWithFlags.enable(:out_of_office_active)

    message = Fixtures.message_fixture(attrs) |> Repo.preload(:contact)
    state = Periodic.run_flows(%{}, message)

    {:ok, %Postgrex.Result{rows: rows}} =
      Repo.query(
        "select id, flow_id from flow_contexts where flow_id = #{state.flows["outofoffice"]}"
      )

    # assert that we have one row which is th outofoffice flow
    assert length(rows) == 1
  end

  test "call the periodic flow function with non-existent flows" do
    state = Periodic.map_flow_ids(%{organization_id: Fixtures.get_org_id()})

    assert {state, false} ==
             Periodic.periodic_flow(state, "doesnotexist", nil, DateTime.utc_now())

    assert {state, false} == Periodic.periodic_flow(state, "daily", nil, DateTime.utc_now())

    {:ok, monday} = Timex.parse("2020-08-10T00:00:00-08:00", "{ISO:Extended}")
    assert {state, false} == Periodic.periodic_flow(state, "monday", nil, monday)
    assert {state, false} == Periodic.periodic_flow(state, "wednesday", nil, monday)
  end
end
