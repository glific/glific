defmodule Glific.Flows.PeriodicTest do
  use Glific.DataCase

  alias Glific.Flows.Periodic

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
    {:ok, sunday} = Timex.parse("2020-08-16T00:00:00-08:00", "{ISO:Extended}")
    assert Periodic.compute_time(monday, "weekly") == monday
    assert Periodic.compute_time(any_day, "weekly") == monday
    assert Periodic.compute_time(sunday, "weekly") == monday

    assert Periodic.compute_time(DateTime.add(monday, 125 * 6 * 60), "monday") == monday
    assert Periodic.compute_time(DateTime.add(monday, 125 * 6 * 60), "daily") == monday
  end
end
