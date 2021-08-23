defmodule Glific.Triggers.Helper do
  @moduledoc """
  The trigger helper for the trigger system that deals with the
  complexity of time queries
  """

  @doc """
  Given a time and the frequency of occurence, compute the next
  time the event can potentially occur
  """
  @spec compute_next(map()) :: DateTime.t() | {:error, any()}
  def compute_next(
        %{
          frequency: frequency,
          days: days,
          next_trigger_at: next_time
        } = _trigger
      ) do
    cond do
      "daily" in frequency -> Timex.shift(next_time, days: 1) |> Timex.to_datetime()
      # "weekly" in frequency -> Timex.shift(time, days: 7) |> Timex.to_datetime()
      "monthly" in frequency -> Timex.shift(next_time, months: 1) |> Timex.to_datetime()
      "weekday" in frequency -> weekday(next_time)
      "weekend" in frequency -> weekend(next_time)
      "none" in frequency -> next_time
      true -> others(next_time, days)
    end
  end

  def compute_next(%{next_trigger_at: next_trigger_at} = _trigger), do: next_trigger_at

  # day of week is a integer: 1 - Monday, 7 - Sunday
  @spec others(DateTime.t(), list()) :: DateTime.t()
  defp others(time, days) do
    # so basically this clause picks a few days of the week
    # we need to loop from current to 7 and then back to current
    # and pick the number of days to shift
    current = Date.day_of_week(time)
    start_list = if current == 7, do: [], else: Enum.to_list((current + 1)..7)

    shift =
      (start_list ++ Enum.to_list(1..current))
      |> Enum.with_index(1)
      |> Enum.filter(fn {x, _shift} -> x in days end)
      |> hd
      |> elem(1)

    Timex.shift(time, days: shift) |> Timex.to_datetime()
  end

  @spec weekday(DateTime.t()) :: DateTime.t()
  defp weekday(time) do
    day_of_week = Date.day_of_week(time)

    if day_of_week < 5,
      do: Timex.shift(time, days: 1) |> Timex.to_datetime(),
      else: Timex.shift(time, days: 8 - day_of_week) |> Timex.to_datetime()
  end

  @spec weekend(DateTime.t()) :: DateTime.t()
  defp weekend(time) do
    day_of_week = Date.day_of_week(time)

    cond do
      day_of_week in [5, 6] -> Timex.shift(time, days: 1) |> Timex.to_datetime()
      day_of_week == 7 -> Timex.shift(time, days: 6) |> Timex.to_datetime()
      true -> Timex.shift(time, days: 6 - day_of_week) |> Timex.to_datetime()
    end
  end
end
