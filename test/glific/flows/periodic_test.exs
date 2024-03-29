defmodule Glific.Flows.PeriodicTest do
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Flows.Periodic,
    Partners,
    Seeds.SeedsDev
  }

  defp reset_cache(organization_id) do
    # first delete the cached organization
    # since we reload the outofoffice flow on every test
    # we have no idea what id the org has cached, hence the forced
    # reload of org cache
    organization = Partners.get_organization!(organization_id)
    Partners.remove_organization_cache(organization.id, organization.shortcode)
    Glific.Caches.remove(organization_id, ["flow_keywords_map"])
  end

  setup %{organization_id: organization_id} do
    reset_cache(organization_id)

    SeedsDev.seed_flow_labels()
    SeedsDev.seed_flows()
    :ok
  end

  test "compute time and its various permutions" do
    # get the beginning of a month
    {:ok, month} = Timex.parse("2020-08-01T00:00:00+00:00", "{ISO:Extended}")
    {:ok, any_day} = Timex.parse("2020-08-13T00:00:00+00:00", "{ISO:Extended}")
    {:ok, last_day} = Timex.parse("2020-08-31T00:00:00+00:00", "{ISO:Extended}")

    assert Periodic.compute_time(month, "monthly") == month
    assert Periodic.compute_time(any_day, "monthly") == month
    assert Periodic.compute_time(last_day, "monthly") == month

    {:ok, monday} = Timex.parse("2020-08-10T00:00:00+00:00", "{ISO:Extended}")
    {:ok, thursday} = Timex.parse("2020-08-13T00:00:00+00:00", "{ISO:Extended}")
    {:ok, sunday} = Timex.parse("2020-08-16T00:00:00+00:00", "{ISO:Extended}")
    assert Periodic.compute_time(monday, "weekly") == monday
    assert Periodic.compute_time(any_day, "weekly") == monday
    assert Periodic.compute_time(sunday, "weekly") == monday

    assert Periodic.compute_time(DateTime.add(monday, 125 * 6 * 60), "monday") == monday
    assert Periodic.compute_time(DateTime.add(monday, 125 * 6 * 60), "daily") == monday

    assert Periodic.compute_time(DateTime.add(thursday, 60 * 6 * 60), "monday") == thursday
    assert Periodic.compute_time(DateTime.add(thursday, 73 * 6 * 60), "daily") == thursday
  end

  test "map flow ids", %{organization_id: organization_id} do
    filled_map = Periodic.map_flow_ids(%{organization_id: organization_id})

    # we know that outofoffice is a default seeded flow
    assert !is_nil(get_in(filled_map, [:flows, "published", "outofoffice"]))
  end

  @start_time elem(Time.new(0, 0, 0, 0), 1)
  @end_time elem(Time.new(0, 0, 0, 1), 1)

  @organization_settings %{
    out_of_office: %{
      enabled: true,
      start_time: @start_time,
      end_time: @end_time,
      flow_id: 1,
      default_flow_id: 3,
      enabled_days: [
        %{id: 1, enabled: true},
        %{id: 2, enabled: true},
        %{id: 3, enabled: true},
        %{id: 4, enabled: true},
        %{id: 5, enabled: true},
        %{id: 6, enabled: true},
        %{id: 7, enabled: true}
      ]
    }
  }

  test "run flows and we know the default flow should get going",
       %{organization_id: organization_id} = attrs do
    FunWithFlags.enable(:enable_out_of_office, for_actor: %{organization_id: organization_id})

    organization = Partners.organization(organization_id)

    organization_settings =
      @organization_settings
      |> put_in([:out_of_office, :start_time], elem(Time.new(0, 0, 0, 0), 1))
      |> put_in([:out_of_office, :end_time], elem(Time.new(23, 59, 59, 999_999), 1))

    # when office hours includes whole day of seven days
    {:ok, _} = Partners.update_organization(organization, organization_settings)
    _organization = Partners.organization(organization.id)

    message = Fixtures.message_fixture(attrs) |> Repo.preload(:contact)
    state = Periodic.run_flows(%{}, message)

    {:ok, %Postgrex.Result{rows: rows}} =
      Repo.query(
        "select id, flow_id from flow_contexts where flow_id = #{state.flows["published"]["defaultflow"]}"
      )

    # assert that we have one row which is th outofoffice flow
    assert length(rows) == 1
  end

  test "run flows and we know the outofoffice flow should get going",
       %{organization_id: organization_id} = attrs do
    FunWithFlags.enable(:enable_out_of_office, for_actor: %{organization_id: organization_id})

    organization = Partners.organization(organization_id)

    # when office hours includes whole day of seven days
    {:ok, _} = Partners.update_organization(organization, @organization_settings)
    _organization = Partners.organization(organization.id)

    message = Fixtures.message_fixture(attrs) |> Repo.preload(:contact)
    state = Periodic.run_flows(%{}, message)

    {:ok, %Postgrex.Result{rows: rows}} =
      Repo.query(
        "select id, flow_id from flow_contexts where flow_id = #{state.flows["published"]["outofoffice"]}"
      )

    # assert that we have one row which is th outofoffice flow
    assert length(rows) == 1
  end

  test "call the periodic flow function with non-existent flows", %{
    organization_id: organization_id
  } do
    state = Periodic.map_flow_ids(%{organization_id: organization_id})

    assert {state, false} ==
             Periodic.periodic_flow(state, "doesnotexist", nil, DateTime.utc_now())

    assert {state, false} == Periodic.periodic_flow(state, "daily", nil, DateTime.utc_now())

    {:ok, monday} = Timex.parse("2020-08-10T00:00:00+00:00", "{ISO:Extended}")
    assert {state, false} == Periodic.periodic_flow(state, "monday", nil, monday)
    assert {state, false} == Periodic.periodic_flow(state, "wednesday", nil, monday)
  end
end
