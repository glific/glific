defmodule Glific.Clients.PehlayAkshar do
  @moduledoc """
  Custom webhook implementation specific to PehlayAkshar use case
  """

  alias Glific.{
    Partners,
    Partners.OrganizationData,
    Repo,
    Sheets.ApiClient
  }

  @sheets %{
    content_sheet:
      "https://docs.google.com/spreadsheets/d/e/2PACX-1vRJbhvPOHrW_y4bwYsgTDu8E8RlT97XNEmvF0bvhlunyaiLEH_Vv6qi07gF4tT6dsYujJ1C-P0VcusF/pub?gid=1348614952&single=true&output=csv"
  }

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("load_content_sheet", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> load_sheet()

    fields
  end

  def webhook("send_daily_msg", fields) do
    today = Timex.format!(DateTime.utc_now(), "{D}/{M}/{YYYY}")
    org_id = Glific.parse_maybe_integer!(fields["organization_id"])

    Repo.fetch_by(OrganizationData, %{
      organization_id: org_id,
      key: "content_sheet"
    })
    |> case do
      {:ok, organization_data} -> Map.get(organization_data.json, today, %{})
      _ -> %{}
    end
  end

  def webhook(_, _) do
    raise "Unknown webhook"
  end

  # @spec load_sheet(String.t(), String.t(), non_neg_integer()) :: :ok
  def load_sheet(org_id) do
    ApiClient.get_csv_content(url: @sheets.content_sheet)
    |> Enum.reduce(%{}, fn {_, row}, acc ->
      Map.put(acc, row["Date"], row)
    end)
    |> then(&Partners.maybe_insert_organization_data("content_sheet", &1, org_id))
  end
end
