defmodule Glific.ReportsTest do
  use Glific.DataCase

  alias Glific.Reports

  test "get_date_preset/3" do
    assert %{today: _, last_day: _, date_map: _} = Reports.get_date_preset()
  end

  test "shifted_time/2 Shift time by no. of days" do
    assert %NaiveDateTime{} = Reports.shifted_time(NaiveDateTime.utc_now(), 2)
  end
end
