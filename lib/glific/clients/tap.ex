defmodule Glific.Clients.Tap do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Flows.ContactField,
    Partners,
    Partners.OrganizationData,
    Repo,
    Sheets.ApiClient
  }

  alias Glific.Sheets.ApiClient

  @props %{
    sheet_links: %{
      activity:
        "https://docs.google.com/spreadsheets/d/e/2PACX-1vQPzJ4BruF8RFMB0DwBgM8Rer7MC0fiL_IVC0rrLtZT7rsa3UnGE3ZTVBRtNdZI9zGXGlQevCajwNcn/pub?gid=89165000&single=true&output=csv",
      quiz:
        "https://docs.google.com/spreadsheets/d/e/2PACX-1vQPzJ4BruF8RFMB0DwBgM8Rer7MC0fiL_IVC0rrLtZT7rsa3UnGE3ZTVBRtNdZI9zGXGlQevCajwNcn/pub?gid=531803735&single=true&output=csv"
    }
  }

  @doc """
  In the case of TAP we retrive the first group the contact is in and store
  and set the remote name to be a sub-directory under that group (if one exists)
  """
  @spec gcs_file_name(map()) :: String.t()
  def gcs_file_name(media) do
    group_name =
      Contact
      |> where([c], c.id == ^media["contact_id"])
      |> join(:inner, [c], cg in ContactGroup, on: c.id == cg.contact_id)
      |> join(:inner, [_c, cg], g in Group, on: cg.group_id == g.id)
      |> select([_c, _cg, g], g.label)
      |> order_by([_c, _cg, g], g.label)
      |> first()
      |> Repo.one()

    if is_nil(group_name),
      do: media["remote_name"],
      else: group_name <> "/" <> media["remote_name"]
  end

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("load_activities", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> load_activities()

    fields
  end

  def webhook("load_quizes", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> load_quizes()

    fields
  end

  def webhook("get_activity_info", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> get_activity_info(fields["date"], fields["type"])
  end

  @spec load_activities(non_neg_integer()) :: :ok
  defp load_activities(org_id) do
    ApiClient.get_csv_content(url: @props.sheet_links.activity)
    |> Enum.each(fn {_, row} ->
      Partners.maybe_insert_organization_data("activities", row, org_id)
    end)
  end

  @spec load_quizes(non_neg_integer()) :: :ok
  defp load_quizes(org_id) do
    ApiClient.get_csv_content(url: @props.sheet_links.quiz)
    |> Enum.each(fn {_, row} ->
      Partners.maybe_insert_organization_data("quizes", row, org_id)
    end)
  end

  @spec get_activity_info(non_neg_integer(), String.t(), String.t()) :: map()
  defp get_activity_info(org_id, date, type) do
    Repo.fetch_by(OrganizationData, %{
      organization_id: org_id,
      key: "activities"
    })
    |> case do
      {:ok, data} ->
        data.json[type][date]
        |> clean_map_keys()

      _ ->
        %{
          is_valid: false,
          message: "Worksheet code not found"
        }
    end
  end

  @spec clean_map_keys(map()) :: map()
  defp clean_map_keys(data) do
    data
    |> Enum.map(fn {k, v} -> {Glific.string_clean(k), v} end)
    |> Enum.into(%{})
  end
end
