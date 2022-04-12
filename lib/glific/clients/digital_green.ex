defmodule Glific.Clients.DigitalGreen do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  require Logger

  alias Glific.{
    Contacts,
    Flows.ContactField,
    Partners,
    Partners.OrganizationData,
    Repo,
    Sheets.ApiClient
  }

  alias Glific.Sheets.ApiClient

  @crp_id_key "dg_crp_ids"

  @geographies %{
    "en" => %{
      "database_key" => "geography_en",
      "sheet_link" => "https://docs.google.com/spreadsheets/d/e/2PACX-1vTYW2yLqES4FGTIDVDIm21XTWsoOPPDaDR8XO0gv32cgydsjcX1d_AaXCuMTNymJhCPzAU-FT1Mont5/pub?gid=1669998910&single=true&output=csv"
    },

    "te" => %{
      "database_key" => "geography_te",
      "sheet_link" => "https://docs.google.com/spreadsheets/d/e/2PACX-1vTYW2yLqES4FGTIDVDIm21XTWsoOPPDaDR8XO0gv32cgydsjcX1d_AaXCuMTNymJhCPzAU-FT1Mont5/pub?gid=752391516&single=true&output=csv"
    }
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
    org_id = Glific.parse_maybe_integer!(fields["organization_id"])
    load_geographies(org_id, @geographies["en"])
    load_geographies(org_id, @geographies["te"])

    fields
  end

  def webhook("get_district_list", fields) do
    org_id = Glific.parse_maybe_integer!(fields["organization_id"])
    region_name = fields["region"]
    langauge = get_language(fields["contact"]["id"])

    get_geographies_data(org_id, @geographies[langauge.locale])
    |> get_in([region_name])
    |> geographies_list_results()
  end

  def webhook("get_division_list", fields) do
    org_id = Glific.parse_maybe_integer!(fields["organization_id"])
    langauge = get_language(fields["contact"]["id"])
    region_name = fields["region"]
    district_name = fields["district"]

    get_geographies_data(org_id, @geographies[langauge.locale])
    |> get_in([region_name, district_name])
    |> geographies_list_results()
  end

  def webhook("get_mandal_list", fields) do
    org_id = Glific.parse_maybe_integer!(fields["organization_id"])
    langauge = get_language(fields["contact"]["id"])
    region_name = fields["region"]
    district_name = fields["district"]
    division_name = fields["division"]

    get_geographies_data(org_id, @geographies[langauge.locale])
    |> get_in([region_name, district_name, division_name, "mandals"])
    |> geographies_list_results()
  end

  def webhook("set_geography", fields) do
    type = fields["type"]
    user_input = fields["selected_index"]
    index_map = Jason.decode!(fields["index_map"])
    contact_id = Glific.parse_maybe_integer!(fields["contact"]["id"])

    if Map.has_key?(index_map, user_input) do
      set_geography(type, index_map[user_input], contact_id)
      %{error: false, message: "Geography set successfully for #{type}"}
    else
      index_map
      |> Enum.find(fn {_index, value} -> String.downcase(value) == String.downcase(user_input) end)
      |> case do
        nil ->
          %{error: true, message: "Invalid selected index"}

        {index, value} ->
          set_geography(type, index_map[index], contact_id)
          %{error: false, message: "Geography set successfully for #{type} and value #{value}"}

        _ ->
          %{error: true, message: "Invalid selected index"}
      end
    end
  end

  def webhook(_, _fields),
    do: %{}

  @spec set_geography(String.t(), String.t(), non_neg_integer()) :: any()
  defp set_geography(type, value, contact_id) do
    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field(type, type, value)
  end

  @spec get_geographies_data(non_neg_integer(), map()) :: map()
  defp get_geographies_data(org_id, geographies_config) do
    {:ok, org_data} =
      Repo.fetch_by(OrganizationData, %{
        organization_id: org_id,
        key: geographies_config["database_key"]
      })

    org_data.json
  end

  @spec geographies_list_results(map() | list()) :: map()
  defp geographies_list_results(resource_map) when resource_map in [nil, %{}] do
    %{error: true, message: "Resource not found"}
  end

  defp geographies_list_results(resource_list) when is_list(resource_list) do
    {index_map, message_list} = format_geographies_message(resource_list)

    %{
      error: false,
      list_message: Enum.join(message_list, "\n"),
      index_map: Jason.encode!(index_map)
    }
    |> Map.merge(convert_to_interactive_message(resource_list))
  end

  defp geographies_list_results(resource_map) do
    {index_map, message_list} =
      Map.keys(resource_map)
      |> format_geographies_message()

    %{
      error: false,
      list_message: Enum.join(message_list, "\n"),
      index_map: Jason.encode!(index_map)
    }
    |> Map.merge(convert_to_interactive_message(Map.keys(resource_map)))
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

  @spec convert_to_interactive_message(list()) :: map()
  defp convert_to_interactive_message(resource_list) do
    list_length = length(resource_list)

    if(list_length > 100) do
      %{
        is_interative: false,
        interative_items_count: 0
      }
    else
      %{
        is_interative: true,
        interative_items_count: list_length,
        interative_data:
          resource_list
          |> Enum.with_index()
          |> Enum.map(fn {value, index} -> {index + 1, value} end)
          |> Enum.into(%{})
      }
    end
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

  defp load_geographies(org_id, geographies_config) do
    ApiClient.get_csv_content(url: geographies_config["sheet_link"])
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
      Partners.maybe_insert_organization_data(geographies_config["database_key"], geographies_data, org_id)
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

  defp get_language(contact_id) do
    contact_id = Glific.parse_maybe_integer!(contact_id)

    contact =
      contact_id
      |> Contacts.get_contact!()
      |> Repo.preload([:language])

    contact.language
  end
end
