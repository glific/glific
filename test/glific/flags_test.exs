defmodule Glific.FlagsTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Fixtures,
    Flags,
    Partners
  }

  setup do
    Flags.init()

    :ok
  end

  @start_time elem(Time.new(0, 0, 0, 0), 1)
  @end_time elem(Time.new(23, 59, 59, 999_999), 1)
  @start_one elem(Time.new(0, 0, 0, 1), 1)

  test "ensure init returns ok, and enabled out of office" do
    organization = Partners.organization(Fixtures.get_org_id())

    status = Flags.init()
    assert status == :ok

    assert FunWithFlags.enabled?(
             :enable_out_of_office,
             for: %{organization_id: organization.id}
           ) == true
  end

  test "check business days combinations" do
    now = DateTime.utc_now()

    # ensure we get the right value for either edge case
    assert Flags.business_day?(now, []) == false
    assert Flags.business_day?(now, Enum.to_list(1..7)) == true

    today = now |> DateTime.to_date() |> Date.day_of_week()
    assert Flags.business_day?(now, [today]) == true
    assert Flags.business_day?(now, Enum.to_list(1..7) -- [today]) == false
  end

  test "check office hours" do
    now = DateTime.utc_now()

    # ensure we get the right value for either edge case
    assert Flags.office_hours?(now, []) == false
    assert Flags.office_hours?(now, [@start_time, @end_time]) == true

    time = now |> DateTime.to_time()

    assert Flags.office_hours?(now, [@start_time, time]) == false
    assert Flags.office_hours?(now, [time, @end_time]) == false

    assert Flags.office_hours?(now, [@start_time, Time.add(time, 60)]) == true
    assert Flags.office_hours?(now, [Time.add(time, -1), @end_time]) == true
  end

  test "ensure enable/disable work as advertised" do
    organization = Partners.organization(Fixtures.get_org_id())

    Flags.enable_out_of_office(organization.id)

    assert FunWithFlags.enabled?(
             :out_of_office_active,
             for: %{organization_id: organization.id}
           ) == true

    Flags.disable_out_of_office(organization.id)

    assert FunWithFlags.enabled?(
             :out_of_office_active,
             for: %{organization_id: organization.id}
           ) == false
  end

  @organization_settings %{
    out_of_office: %{
      enabled: true,
      start_time: @start_time,
      end_time: @end_time,
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

  test "check out of office should activate out_of_office_active flag" do
    organization = Partners.organization(Fixtures.get_org_id())

    # when office hours includes whole day of seven days
    {:ok, _} = Partners.update_organization(organization, @organization_settings)
    Flags.out_of_office_check(organization.id)

    assert FunWithFlags.enabled?(
             :out_of_office_active,
             for: %{organization_id: organization.id}
           ) == false
  end

  test "check out of office should de-activate out_of_office_active flag" do
    organization = Partners.organization(Fixtures.get_org_id())

    # when office hours is zero
    organization_settings =
      put_in(@organization_settings, [:out_of_office, :end_time], @start_one)

    # when office hours includes just one microsecond of the day
    {:ok, _} = Partners.update_organization(organization, organization_settings)
    Flags.out_of_office_check(organization.id)

    assert FunWithFlags.enabled?(
             :out_of_office_active,
             for: %{organization_id: organization.id}
           ) == true
  end

  test "update out of office should deactivate out of office if disabled" do
    organization = Partners.organization(Fixtures.get_org_id())

    # when office hours is zero
    new_organization_settings =
      put_in(@organization_settings, [:out_of_office, :end_time], @start_one)

    {:ok, _} = Partners.update_organization(organization, new_organization_settings)
    Flags.out_of_office_check(organization.id)

    assert FunWithFlags.enabled?(
             :out_of_office_active,
             for: %{organization_id: organization.id}
           ) == true

    # When flag is disabled
    FunWithFlags.disable(:enable_out_of_office, for_actor: %{organization_id: organization.id})
    Flags.out_of_office_update(organization.id)

    assert FunWithFlags.enabled?(
             :out_of_office_active,
             for: %{organization_id: organization.id}
           ) == false
  end
end
