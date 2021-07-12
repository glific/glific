defmodule Glific.Clients.DigitalGreen do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Flows.ContactField,
    Groups,
    Groups.Group,
    Navanatech,
    Repo
  }

  alias Glific.Sheets.ApiClient

  @stage_1 "stage 1"
  @stage_2 "stage 2"
  @stage_3 "stage 3"
  @stage_1_threshold 26
  @stage_2_threshold 40
  @stage_3_threshold 60

  @weather_updates %{
    "temp_threshold" =>  35,
    "humidity_threshold" => 95,
    "published_csv" => "https://docs.google.com/spreadsheets/d/e/2PACX-1vS-GAeslOLrmyeYBTEqcQ3IkOeY85BAAsTaRc9bUxEnzbIf8QAn5_uLjg0zgMgkmqZLt5HSM9BwTEjL/pub?gid=729435971&single=true&output=csv"
  }

  @doc """
  Returns time in second till next defined Timeslot
  """
  @spec time_till_next_slot(DateTime.t()) :: non_neg_integer()
  def time_till_next_slot(time \\ DateTime.utc_now()) do
    current_time = Timex.now() |> Timex.beginning_of_day()
    # Morning slot at 7am
    morning_slot = current_time |> Timex.shift(hours: 7)
    # Evening slot at 6:30pm
    evening_slot = current_time |> Timex.shift(hours: 18, minutes: 30)

    ## get next define slots
    next_slot =
      if Timex.compare(time, morning_slot, :seconds) == -1, do: morning_slot, else: evening_slot

    next_slot
    |> Timex.diff(time, :seconds)

    ## the minmum wait unit in glific is 1 minute.
    max(next_slot, 61)
  end

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("daily", fields) do
    {:ok, contact_id} = Glific.parse_maybe_integer(fields["contact_id"])
    {:ok, organization_id} = Glific.parse_maybe_integer(fields["organization_id"])

    next_flow = fields["contact"]["fields"]["next_flow"]["value"]

    next_flow_at =
      fields["contact"]["fields"]["next_flow_at"]["value"]
      |> String.trim()
      |> format_date

    add_to_next_flow_group(
      next_flow,
      next_flow_at,
      contact_id,
      organization_id
    )

    fields
  end

  def webhook("total_days", fields) do
    {:ok, contact_id} = Glific.parse_maybe_integer(fields["contact_id"])
    {:ok, organization_id} = Glific.parse_maybe_integer(fields["organization_id"])

    {:ok, initial_crop_day} =
      Glific.parse_maybe_integer(fields["contact"]["fields"]["initial_crop_day"]["value"])

    enrolled_date = format_date(fields["contact"]["fields"]["enrolled_day"]["value"])
    days_since_enrolled = Timex.now() |> Timex.diff(enrolled_date, :days)
    total_days = days_since_enrolled + initial_crop_day

    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field("total_days", "total_days", total_days, "string")

    move_to_group(total_days, contact_id, organization_id)
  end

  def webhook("crop_stage", fields) do
    {:ok, contact_id} = Glific.parse_maybe_integer(fields["contact_id"])
    update_crop_days(fields["crop_stage"], contact_id)
    fields
  end

  def webhook("navanatech", fields) do
    Navanatech.navatech_post(fields)
  end

  def webhook("weather_updates", fields) do
    today = Timex.today()

    opts = [
      start_date: Timex.beginning_of_week(today, :mon),
      end_date: Timex.end_of_week(today, :sun),
      village: String.downcase(fields["village_name"])
    ]

    ApiClient.get_csv_content(url: @weather_updates["published_csv"])
    |> Enum.reduce([], fn {_, row}, acc -> filter_weather_records(row, acc, opts) end)
    |> generate_weather_results()
  end

  def webhook(_, _fields),
    do: %{}

  ## filter record based on the contact village, and current week.
  @spec filter_weather_records(map(), list(), Keyword.t()) :: list()
  defp filter_weather_records(row, acc, opts) do
    village = Keyword.get(opts, :village, "")
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)

    row_village = String.downcase(row["Village"])

    row_date =
      Timex.parse!(row["Date"], "{M}/{D}/{YYYY}")
      |> Timex.to_date()

    row = Map.put(row, :date_struct, row_date)

    if String.contains?(row_village, village) and Timex.between?(row_date, start_date, end_date, inclusive: true),
      do: [row] ++ acc,
      else: acc
  end

  ## filter record based on the contact village, and current week.
  @spec generate_weather_results(list()) :: map()
  defp generate_weather_results(rows) do
    %{message: "", is_extream_condition: false}
    |> generate_weather_message(rows)
    |> check_for_extream_condition(rows)
  end

  defp generate_weather_message(results, rows) do
    message =
      Enum.map(rows, fn row -> "Date: #{row["Date"]} Summery: #{row["Summary"]}" end)
      |> Enum.join("\n")

    Map.put(results, :message, message)
  end

  @spec check_for_extream_condition(map(), list()) :: map()
  defp check_for_extream_condition(results, rows) do
    {tempratures, humidity} =
      Enum.reduce(rows, {[], []}, fn row, {t, h} ->
        tempratures = t ++ [clean_weather_record(row["Temperature"])]
        humidity = h ++ [clean_weather_record(row["Relative humidity"])]
        {tempratures, humidity}
      end)

    extream_condition = extream_condition_type(tempratures, humidity)

    results
    |> Map.put(:is_extream_condition, (extream_condition in ["temp", "humidity"]))
    |> Map.put(:extream_condition_type, extream_condition)

  end

  @spec extream_condition_type(list(), list()) :: String.t()
  defp extream_condition_type(tempratures, humidity) do
    is_high_temp = Enum.any?(tempratures, fn t -> t >= @weather_updates["temp_threshold"] end)
    is_high_humidity = Enum.any?(humidity, fn h -> h >= @weather_updates["humidity_threshold"] end)
    cond do
      is_high_temp -> "temp"
      is_high_humidity -> "humidity"
      true -> "none"
    end
  end

  @spec clean_weather_record(String.t()) :: String.t()
  defp clean_weather_record(record) when is_binary(record) do
    record
    |> String.replace(["°C", "%", "C", "°"], "")
    |> String.trim()
    |> Glific.parse_maybe_integer()
    |> elem(1)
  end

  defp clean_weather_record(str), do: str

  defp update_crop_days(@stage_1, contact_id) do
    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field("initial_crop_day", "initial_crop_day", "17", "string")
  end

  defp update_crop_days(@stage_2, contact_id) do
    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field("initial_crop_day", "initial_crop_day", "32", "string")
  end

  defp update_crop_days(@stage_3, contact_id) do
    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field("initial_crop_day", "initial_crop_day", "47", "string")
  end

  defp update_crop_days(_, contact_id) do
    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field("initial_crop_day", "initial_crop_day", "0", "string")
  end

  @spec move_to_group(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: :ok
  defp move_to_group(0, contact_id, organization_id) do
    {:ok, stage_one_group} =
      Repo.fetch_by(Group, %{label: @stage_1, organization_id: organization_id})

    Groups.create_contact_group(%{
      contact_id: contact_id,
      group_id: stage_one_group.id,
      organization_id: organization_id
    })

    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field("crop_stage", "crop_stage", @stage_1, "string")

    :ok
  end

  defp move_to_group(@stage_1_threshold, contact_id, organization_id) do
    with {:ok, stage_one_group} <-
           Repo.fetch_by(Group, %{label: @stage_1, organization_id: organization_id}),
         {:ok, stage_two_group} <-
           Repo.fetch_by(Group, %{label: @stage_2, organization_id: organization_id}) do
      Groups.create_contact_group(%{
        contact_id: contact_id,
        group_id: stage_two_group.id,
        organization_id: organization_id
      })

      Contacts.get_contact!(contact_id)
      |> ContactField.do_add_contact_field("crop_stage", "crop_stage", @stage_2, "string")

      Groups.delete_group_contacts_by_ids(stage_one_group.id, [contact_id])
    end

    :ok
  end

  defp move_to_group(@stage_2_threshold, contact_id, organization_id) do
    with {:ok, stage_three_group} <-
           Repo.fetch_by(Group, %{label: @stage_3, organization_id: organization_id}),
         {:ok, stage_two_group} <-
           Repo.fetch_by(Group, %{label: @stage_2, organization_id: organization_id}) do
      Groups.create_contact_group(%{
        contact_id: contact_id,
        group_id: stage_three_group.id,
        organization_id: organization_id
      })

      Contacts.get_contact!(contact_id)
      |> ContactField.do_add_contact_field("crop_stage", "crop_stage", @stage_3, "string")

      Groups.delete_group_contacts_by_ids(stage_two_group.id, [contact_id])
    end

    :ok
  end

  defp move_to_group(@stage_3_threshold, contact_id, organization_id) do
    {:ok, stage_three_group} =
      Repo.fetch_by(Group, %{label: @stage_3, organization_id: organization_id})

    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field("crop_stage", "crop_stage", "completed", "string")

    Groups.delete_group_contacts_by_ids(stage_three_group.id, [contact_id])

    :ok
  end

  defp move_to_group(_, _contact_id, _organization_id), do: :ok

  @spec add_to_next_flow_group(String.t(), Date.t(), non_neg_integer(), non_neg_integer()) :: :ok
  defp add_to_next_flow_group(next_flow, next_flow_at, contact_id, organization_id) do
    with 0 <- Timex.diff(Timex.now(), next_flow_at, :days),
         {:ok, next_flow_group} <-
           Repo.fetch_by(Group, %{label: next_flow, organization_id: organization_id}) do
      Groups.create_contact_group(%{
        contact_id: contact_id,
        group_id: next_flow_group.id,
        organization_id: organization_id
      })
    end

    :ok
  end

  @spec format_date(String.t()) :: Date.t()
  defp format_date(date) do
    date
    |> Timex.parse!("{YYYY}-{0M}-{D}")
    |> Timex.to_date()
  end
end
