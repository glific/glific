defmodule Glific.FlagsTest do
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Flags,
    Partners
  }

  setup do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "status" => "success",
              "users" => []
            })
        }
    end)

    :ok
  end

  @start_time elem(Time.new(0, 0, 0, 0), 1)
  @end_time elem(Time.new(23, 59, 59, 999_999), 1)
  @start_one elem(Time.new(0, 0, 0, 1), 1)

  test "ensure init returns ok, and enabled out of office" do
    organization = Partners.organization(Fixtures.get_org_id())

    status = Flags.init(organization)
    assert status == nil

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

  test "disable org settings and ensure nothing happens" do
    organization = Fixtures.organization_fixture()

    # when office hours includes whole day of seven days
    {:ok, _} =
      Partners.update_organization(
        organization,
        put_in(@organization_settings, [:out_of_office, :enabled], false)
      )

    organization = Partners.organization(organization.id)
    Flags.out_of_office_check(organization)

    assert FunWithFlags.enabled?(
             :out_of_office_active,
             for: %{organization_id: organization.id}
           ) == false

    # also might as well check update
    Flags.out_of_office_update(organization.id)

    assert FunWithFlags.enabled?(
             :out_of_office_active,
             for: %{organization_id: organization.id}
           ) == false
  end

  test "out_of_office_check/1 should de-activate out_of_office_active flag" do
    organization = Fixtures.organization_fixture()

    # when office hours includes whole day of seven days
    {:ok, _} = Partners.update_organization(organization, @organization_settings)
    organization = Partners.organization(organization.id)
    Flags.out_of_office_check(organization)

    assert FunWithFlags.enabled?(
             :out_of_office_active,
             for: %{organization_id: organization.id}
           ) == false
  end

  test "out_of_office_check/1 should activate out_of_office_active flag" do
    organization = Fixtures.organization_fixture()

    # when office hours is zero
    organization_settings =
      put_in(@organization_settings, [:out_of_office, :end_time], @start_one)

    # when office hours includes just one microsecond of the day
    {:ok, organization} = Partners.update_organization(organization, organization_settings)
    organization = Partners.organization(organization.id)
    Flags.out_of_office_check(organization)

    assert FunWithFlags.enabled?(
             :out_of_office_active,
             for: %{organization_id: organization.id}
           ) == true
  end

  test "out_of_office_update/1 should activate / de-activate out_of_office_active flag" do
    organization = Fixtures.organization_fixture()

    # when office hours is zero
    new_organization_settings =
      put_in(@organization_settings, [:out_of_office, :end_time], @start_one)

    {:ok, organization} = Partners.update_organization(organization, new_organization_settings)
    organization = Partners.organization(organization.id)
    Flags.out_of_office_update(organization)

    assert FunWithFlags.enabled?(
             :out_of_office_active,
             for: %{organization_id: organization.id}
           ) == true

    # When flag is disabled
    FunWithFlags.disable(:enable_out_of_office, for_actor: %{organization_id: organization.id})
    Flags.out_of_office_update(organization)

    assert FunWithFlags.enabled?(
             :out_of_office_active,
             for: %{organization_id: organization.id}
           ) == false
  end

  test "get_flag_enabled/2 correctly reflects unified_api_enabled flag state" do
    organization = Fixtures.organization_fixture()

    FunWithFlags.enable(:unified_api_enabled, for_actor: %{organization_id: organization.id})
    assert Flags.get_flag_enabled(:unified_api_enabled, organization) == true

    FunWithFlags.disable(:unified_api_enabled, for_actor: %{organization_id: organization.id})
    assert Flags.get_flag_enabled(:unified_api_enabled, organization) == false
  end
end
