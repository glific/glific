defmodule Glific.Clients.DigitalGreen do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  require Logger

  alias Glific.{
    Partners,
    Partners.OrganizationData,
    Repo,
    Sheets.ApiClient
  }

  alias Glific.Sheets.ApiClient

  @crp_id_key "dg_crp_ids"

  @geographies %{
    database_key: "geography",
    sheet_link:
      "https://docs.google.com/spreadsheets/d/e/2PACX-1vTYW2yLqES4FGTIDVDIm21XTWsoOPPDaDR8XO0gv32cgydsjcX1d_AaXCuMTNymJhCPzAU-FT1Mont5/pub?gid=1669998910&single=true&output=csv"
  }

  @doc """
  Returns time in second till next defined Timeslot
  """
  @spec time_till_next_slot(DateTime.t()) :: non_neg_integer()
  def time_till_next_slot(time \\ DateTime.utc_now()) do
    current_time = Timex.now() |> Timex.beginning_of_day()
    # Morning slot at 6am IST
    morning_slot = Timex.shift(current_time, hours: 0, minutes: 30)
    # Evening slot at 6:30pm IST
    evening_slot = Timex.shift(current_time, hours: 12, minutes: 30)

    # the minimum wait unit in Glific is 1 minute
    next_slot(time, morning_slot, evening_slot)
    |> Timex.diff(time, :seconds)
    |> max(61)
  end

  defp next_slot(time, morning_slot, evening_slot) do
    # Setting next defined slot to nearest next defined slot
    cond do
      Timex.compare(time, morning_slot, :seconds) < 0 ->
        morning_slot

      Timex.compare(time, evening_slot, :seconds) < 0 ->
        evening_slot

      # Setting next defined slot to next day morning slot
      true ->
        Timex.shift(morning_slot, days: 1)
    end
  end

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("load_crp_ids", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> load_crp_ids()

    fields
  end

  def webhook("validate_crp_id", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> validate_crp_id(fields["crp_id"])
  end

  def webhook("load_geography", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> load_geographies()

    fields
  end

  def webhook("get_district_list", fields) do
    org_id = Glific.parse_maybe_integer!(fields["organization_id"])
    region_name = fields["region"]

    get_geographies_data(org_id)
    |> get_in([region_name])
    |> geographies_list_results()
  end

  def webhook("get_division_list", fields) do
    org_id = Glific.parse_maybe_integer!(fields["organization_id"])
    region_name = fields["region"]
    district_name = fields["district"]

    get_geographies_data(org_id)
    |> get_in([region_name, district_name])
    |> geographies_list_results()
  end

  def webhook("get_mandal_list", fields) do
    org_id = Glific.parse_maybe_integer!(fields["organization_id"])
    region_name = fields["region"]
    district_name = fields["district"]
    division_name = fields["division"]

    get_geographies_data(org_id)
    |> get_in([region_name, district_name, division_name, "mandals"])
    |> geographies_list_results()
  end

  def webhook(_, _fields),
    do: %{}

  @spec get_geographies_data(non_neg_integer()) :: map()
  defp get_geographies_data(org_id) do
    {:ok, org_data} =
      Repo.fetch_by(OrganizationData, %{
        organization_id: org_id,
        key: @geographies.database_key
      })

    org_data.json
  end

  @spec geographies_list_results(map()) :: map()
  defp geographies_list_results(resource_list) when resource_list in [nil, %{}] do
    %{error: true, message: "Resource not found"}
  end

  defp geographies_list_results(resource_list) do
    {index_map, message_list} =
      Map.keys(resource_list)
      |> format_geographies_message()

    %{
      error: false,
      list_message: Enum.join(message_list, "\n"),
      index_map: index_map
    }
  end

  @spec format_geographies_message(list()) :: {map(), list()}
  defp format_geographies_message(districts) do
    districts
    |> Enum.with_index(1)
    |> Enum.reduce({%{}, []}, fn {district, index}, {index_map, message_list} ->
      {
        Map.put(index_map, index, district),
        message_list ++ ["Type *#{index}* for #{district}"]
      }
    end)
  end

  @spec load_crp_ids(any) :: %{status: <<_::88>>}
  defp load_crp_ids(org_id) do
    ApiClient.get_csv_content(url: "https://storage.googleapis.com/dg_voicebot/crp_ids.csv")
    |> Enum.reduce(%{}, fn {_, row}, acc ->
      crp_id = row["Employee Id"]
      if crp_id in [nil, ""], do: acc, else: Map.put(acc, Glific.string_clean(crp_id), row)
    end)
    |> then(fn crp_data ->
      Partners.maybe_insert_organization_data(@crp_id_key, crp_data, org_id)
    end)

    %{status: "successfull"}
  end

  defp validate_crp_id(org_id, crp_id) do
    crp_id = Glific.string_clean(crp_id)

    {:ok, org_data} =
      Repo.fetch_by(OrganizationData, %{
        organization_id: org_id,
        key: @crp_id_key
      })

    %{
      is_vaid: Map.has_key?(org_data.json, crp_id)
    }
  end

  defp load_geographies(org_id) do
    ApiClient.get_csv_content(url: @geographies.sheet_link)
    |> Enum.reduce(%{}, fn {_, row}, acc ->
      region = row["Region Name"]
      district = row["Proposed District"]
      division = row["Proposed Division"]
      mandal = row["Mandal"]

      region_map = Map.get(acc, region, %{})
      district_map = Map.get(region_map, district, %{})
      division_map = Map.get(district_map, division, %{})
      mandals = Map.get(division_map, "mandals", [])

      division_map = Map.merge(division_map, %{"mandals" => mandals ++ [mandal]})

      district_map = Map.put(district_map, division, division_map)

      region_map = Map.put(region_map, district, district_map)

      Map.put(acc, region, region_map)
    end)
    |> then(fn geographies_data ->
      Partners.maybe_insert_organization_data(@geographies.database_key, geographies_data, org_id)
    end)
  end

  @doc """
  A callback function to support daily tasks for the client
  in the backend.
  """
  @spec daily_tasks(non_neg_integer()) :: atom()
  def daily_tasks(_org_id) do
    # we have added the background flows and now don't need this.
    # fetch_contacts_from_farmer_group(org_id)
    # |> Enum.each(&run_daily_task/1)
    :ok
  end
end
