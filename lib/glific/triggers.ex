defmodule Glific.Triggers do
  @moduledoc """
  The trigger manager for all the trigger system that starts flows
  within Glific
  """

  @doc """
  Given a time and the frequency of occurence, compute the next
  time the event can potentially occur
  """
  @spec compute_next_time(DateTime.t(), String.t()) :: DateTime.t()
  def compute_next_time(current_time, frequency)
      when frequency in ["today", "daily", "weekly", "monthly"] do
    case frequency do
      "today" ->
        current_time

      "daily" ->
        Timex.shift(current_time, days: 1)

      "weekly" ->
        Timex.shift(current_time, days: 7)

      "monthly" ->
        Timex.shift(current_time, months: 1)
    end
  end

  def compute_next_time(current_time, frequency)
      when frequency in ["weekday", "weekend"] do
    case frequency do
      "weekday" ->
        day_of_week = Date.day_of_week(current_time)

        if day_of_week < 5,
          do: Timex.shift(current_time, days: 1),
          else: Timex.shift(current_time, days: 8 - day_of_week)

      "weekend" ->
        day_of_week = Date.day_of_week(current_time)

        cond do
          day_of_week in [5, 6] -> Timex.shift(current_time, days: 1)
          day_of_week == 7 -> Timex.shift(current_time, days: 6)
          true -> Timex.shift(current_time, days: 6 - day_of_week)
        end
    end
  end
end
