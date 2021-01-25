defmodule Glific.Triggers.Helper do
  @moduledoc """
  The trigger helper for the trigger system that deals with the
  complexity of time queries
  """

  alias Glific.Triggers.Trigger

  @doc """
  Given a time and the frequency of occurence, compute the next
  time the event can potentially occur
  """
  @spec compute_next(Trigger.t()) :: DateTime.t()
  def compute_next(%{last_trigger_at: time, repeats: repeats} = _trigger) do
    cond do
      "daily" in repeats -> Timex.shift(time, days: 1)
      "weekly" in repeats -> Timex.shift(time, days: 7)
      "monthly" in repeats -> Timex.shift(time, months: 1)
      "weekday" in repeats -> weekday(time)
      "weekend" in repeats -> weekend(time)
      true -> others(time, repeats)
    end
  end

  # day of week is a integer: 1 - Monday, 7 - Sunday
  @spec others(DateTime.t(), list()) :: DateTime.t()
  defp others(time, repeats) do
    # so basically this clause picks a few days of the week
    # we need to loop from current to 7 and then back to current
    # and pick the number of days to shift
    current = Date.day_of_week(time)

    start_list = if current == 7, do: [], else: Enum.to_list((current + 1)..7)

    shift =
      (start_list ++ Enum.to_list(1..current))
      |> Enum.map(&Integer.to_string/1)
      |> Enum.with_index(1)
      |> Enum.filter(fn {x, _shift} -> x in repeats end)
      |> hd
      |> elem(1)

    Timex.shift(time, days: shift)
  end

  @spec weekday(DateTime.t()) :: DateTime.t()
  defp weekday(time) do
    day_of_week = Date.day_of_week(time)

    if day_of_week < 5,
      do: Timex.shift(time, days: 1),
      else: Timex.shift(time, days: 8 - day_of_week)
  end

  @spec weekend(DateTime.t()) :: DateTime.t()
  defp weekend(time) do
    day_of_week = Date.day_of_week(time)

    cond do
      day_of_week in [5, 6] -> Timex.shift(time, days: 1)
      day_of_week == 7 -> Timex.shift(time, days: 6)
      true -> Timex.shift(time, days: 6 - day_of_week)
    end
  end
end
