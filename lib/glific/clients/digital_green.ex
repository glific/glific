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

  @doc """
  Returns time in second till next defined Timeslot
  """
  @spec time_till_next_slot(DateTime.t()) :: non_neg_integer()
  def time_till_next_slot(time \\ DateTime.utc_now()) do
    # Morning slot at 7am
    morning_slot = Timex.now() |> Timex.beginning_of_day() |> Timex.shift(hours: 7)

    # Evening slot at 6:30pm
    evening_slot = Timex.now() |> Timex.beginning_of_day() |> Timex.shift(hours: 18, minutes: 30)

    next_slot =
      if Timex.compare(time, morning_slot, :seconds) == -1, do: morning_slot, else: evening_slot

    next_slot
    |> Timex.diff(time, :seconds)
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

  @published_csv_weather_updates "https://docs.google.com/spreadsheets/d/e/2PACX-1vS-GAeslOLrmyeYBTEqcQ3IkOeY85BAAsTaRc9bUxEnzbIf8QAn5_uLjg0zgMgkmqZLt5HSM9BwTEjL/pub?gid=729435971&single=true&output=csv"

  def webhook("weather_updates", fields) do
    today = Timex.today()

    opts = [
      start_date: Timex.beginning_of_week(today, :mon),
      end_date: Timex.end_of_week(today, :sun),
      village: String.downcase(fields["village_name"])
    ]

    ApiClient.get_csv_content(url: @published_csv_weather_updates)
    |> Enum.reduce([], fn {_, row}, acc -> filter_weather_records(row, acc, opts) end)
    |> generate_weather_results()
  end

  def webhook(_, _fields),
    do: %{}

  defp filter_weather_records(row, acc, opts) do
    village = Keyword.get(opts, :village, "")
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)

    row_village = String.downcase(row["Village"])

    row_date =
      Timex.parse!(row["Date"], "{M}/{D}/{YYYY}")
      |> Timex.to_date()

    row = Map.put(row, :date_struct, row_date)

    if String.contains?(row_village, village) and Timex.between?(row_date, start_date, end_date),
      do: [row] ++ acc,
      else: acc
  end

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

  defp check_for_extream_condition(results, rows) do
    is_extream =
      rows
      |> Enum.find(false, fn row -> row["Is_extream_condition"] == "yes" end)

    {tempratures, humidity} =
      Enum.reduce(rows, {[], []}, fn row, {t, h} ->
        tempratures = t ++ [row["Temperature"]]
        humidity = h ++ [row["Relative humidity"]]

        {tempratures, humidity}
      end)

    IO.inspect(tempratures)
    IO.inspect(humidity)

    Enum.max(tempratures)
    |> IO.inspect()

    Enum.max(humidity)
    |> IO.inspect()



    Map.put(results, :is_extream_condition, is_map(is_extream))
  end

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
