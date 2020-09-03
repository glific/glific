defmodule Glific.FlagsTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Flags,
  }

  setup do
    :ok
  end

  test "ensure init returns ok, and enabled out of office" do
    {status, _} = Flags.init()
    assert status == :ok
    assert FunWithFlags.enabled?(:enable_out_of_office) == true
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
    {:ok, start_time} = Time.new(0, 0, 0, 0)
    {:ok, end_time} =  Time.new(23, 59, 59, 999_999)

    # ensure we get the right value for either edge case
    assert Flags.office_hours?(now, []) == false
    assert Flags.office_hours?(now, [start_time, end_time]) == true

    time = now |> DateTime.to_time()

    assert Flags.office_hours?(now, [start_time, time]) == false
    assert Flags.office_hours?(now, [time, end_time]) == false

    assert Flags.office_hours?(now, [start_time, Time.add(time, 60)]) == true
    assert Flags.office_hours?(now, [Time.add(time, -1), end_time]) == true
  end
end
