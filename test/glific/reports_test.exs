defmodule Glific.ReportsTest do
  use Glific.DataCase

  alias Glific.Reports

  test "get_date_preset/3" do
    end_day = NaiveDateTime.utc_now() |> Timex.beginning_of_day()

    start_day =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-7, :day)
      |> Timex.beginning_of_day()

    date_range = %{
      end_day: end_day,
      start_day: start_day
    }

    assert %{end_day: _, start_day: _, date_map: _} = Reports.get_date_preset(date_range)
  end
end
