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
        } = trigger
      ) do
    cond do
      "daily" in frequency ->
        Timex.shift(next_time, days: 1) |> Timex.to_datetime()

      # "weekly" in frequency -> Timex.shift(time, days: 7) |> Timex.to_datetime()
      "hourly" in frequency ->
        Map.get(trigger, :hours, [])
        |> compute_hourly(next_time)

      "monthly" in frequency ->
        monthly(next_time, days)

      "weekday" in frequency ->
        weekday(next_time)

      "weekend" in frequency ->
        weekend(next_time)

      "none" in frequency ->
        next_time

      true ->
        others(next_time, days)
    end
  end

  def compute_next(%{next_trigger_at: next_trigger_at} = _trigger), do: next_trigger_at

  # day of week is a integer: 1 - Monday, 7 - Sunday
  @spec others(DateTime.t(), list()) :: DateTime.t()
  def others(time, []), do: time

  def others(time, days) do
    # so basically this clause picks a few days of the week
    # we need to loop from current to 7 and then back to current
    # and pick the number of days to shift
    current = Date.day_of_week(time)
    start_list = if current == 7, do: [], else: Enum.to_list((current + 1)..7)

    shift = shift_duration(start_list, days, current)

    Timex.shift(time, days: shift) |> Timex.to_datetime()
  end

  @spec shift_duration(list(), list(), integer()) :: integer()
  defp shift_duration(start_list, measures, current) do
    (start_list ++ Enum.to_list(1..current))
    |> Enum.with_index(1)
    |> Enum.filter(fn {x, _shift} -> x in measures end)
    |> hd
    |> elem(1)
  end

  @spec compute_hourly(list(), DateTime.t()) :: DateTime.t()
  defp compute_hourly(hours, time) do
    current = time.hour
    start_list = if current == 23, do: [], else: Enum.to_list((current + 1)..23)

    shift = shift_duration(start_list, hours, current)

    Timex.shift(time, hours: shift) |> Timex.to_datetime()
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

  @spec monthly_days_in_order(list()) :: list()
  defp monthly_days_in_order(days) do
    Enum.map(days, fn day ->
      {:ok, number} = Glific.parse_maybe_integer(day)
      number
    end)
    |> Enum.sort(&(&1 <= &2))
  end

  @spec monthly_days_to_shift(map()) :: integer()
  defp monthly_days_to_shift(%{
         days_in_order: days_in_order,
         day_of_month: day_of_month,
         total_days_in_month: total_days_in_month,
         least_day: least_day,
         max_day: max_day,
         time: time
       }) do
    cond do
      day_of_month < least_day ->
        least_day - day_of_month

      day_of_month >= max_day ->
        ## we can probably do that in a elixir way. Doing that for now to make it more readable
        remaining_days = total_days_in_month - day_of_month
        total_days_next_month = time |> Timex.shift(months: 1) |> Date.days_in_month()

        {least_day, _max_day} = monthly_day_range(days_in_order, total_days_next_month)

        remaining_days + least_day

      true ->
        Enum.find(days_in_order, &(&1 > day_of_month)) - day_of_month
    end
  end

  @spec monthly_day_range(list(), integer()) :: tuple()
  defp monthly_day_range(days_in_order, total_days_in_month) do
    least_day = days_in_order |> hd()
    max_day = days_in_order |> List.last()

    least_day = if total_days_in_month <= least_day, do: total_days_in_month, else: least_day
    max_day = if total_days_in_month <= max_day, do: total_days_in_month, else: max_day
    {least_day, max_day}
  end

  @spec monthly(DateTime.t(), list()) :: DateTime.t()
  defp monthly(time, days) do
    day_of_month = Timex.format!(time, "{D}") |> String.to_integer()
    total_days_in_month = Date.days_in_month(time)
    days_in_order = monthly_days_in_order(days)
    {least_day, max_day} = monthly_day_range(days_in_order, total_days_in_month)

    days_to_shift =
      monthly_days_to_shift(%{
        days_in_order: days_in_order,
        day_of_month: day_of_month,
        total_days_in_month: total_days_in_month,
        least_day: least_day,
        max_day: max_day,
        time: time
      })

    Timex.shift(time, days: days_to_shift) |> Timex.to_datetime()
  end
end
