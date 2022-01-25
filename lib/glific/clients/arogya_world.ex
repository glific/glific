defmodule Glific.Clients.ArogyaWorld do
  @start_date "2022-01-24"

  defp start_date() do
    @start_date
    |> Timex.parse!("{YYYY}-{0M}-{D}")
    |> Timex.to_date()
  end

  def get_week do
    Timex.diff(Timex.today(), start_date(), :weeks)
  end

  def current_week_and_day() do
    week_day = Timex.weekday(start_date())
    day_name = Timex.day_name(week_day)
    {get_week(), Timex.weekday(Timex.today()), day_name}
  end
end
