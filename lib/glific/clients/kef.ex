defmodule Glific.Clients.KEF do
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

  @props %{
    worksheets: %{
      sheet_links: %{
        prekg:
          "https://docs.google.com/spreadsheets/d/e/2PACX-1vQPzJ4BruF8RFMB0DwBgM8Rer7MC0fiL_IVC0rrLtZT7rsa3UnGE3ZTVBRtNdZI9zGXGlQevCajwNcn/pub?gid=89165000&single=true&output=csv",
        lkg:
          "https://docs.google.com/spreadsheets/d/e/2PACX-1vQPzJ4BruF8RFMB0DwBgM8Rer7MC0fiL_IVC0rrLtZT7rsa3UnGE3ZTVBRtNdZI9zGXGlQevCajwNcn/pub?gid=531803735&single=true&output=csv",
        ukg:
          "https://docs.google.com/spreadsheets/d/e/2PACX-1vQPzJ4BruF8RFMB0DwBgM8Rer7MC0fiL_IVC0rrLtZT7rsa3UnGE3ZTVBRtNdZI9zGXGlQevCajwNcn/pub?gid=1715409890&single=true&output=csv"
      }
    }
  }

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("load_worksheets", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> load_worksheets()

    fields
  end

  def webhook("validate_worksheet_code", fields) do
    status =
      Glific.parse_maybe_integer!(fields["organization_id"])
      |> validate_worksheet_code(fields["worksheet_code"])

    %{
      is_vaid: status
    }
  end

  defp load_worksheets(org_id) do
    @props.worksheets.sheet_links
    |> Enum.each(fn {k, v} -> do_load_code_worksheet(k, v, org_id) end)

    %{status: "successfull"}
  end

  defp validate_worksheet_code(org_id, worksheet_code) do
    worksheet_code = Glific.string_clean(worksheet_code)

    Repo.fetch_by(OrganizationData, %{
      organization_id: org_id,
      key: worksheet_code
    })
    |> case do
      {:ok, _data} -> true
      _ -> false
    end
  end

  defp do_load_code_worksheet(class, sheet_link, org_id) do
    ApiClient.get_csv_content(url: sheet_link)
    |> Enum.reduce(%{}, fn {_, row}, acc ->
      code = Glific.string_clean(row["code"])

      crp_id = row["Employee Id"]
      if crp_id in [nil, ""], do: acc, else: Map.put(acc, Glific.string_clean(crp_id), row)
    end)
    |> then(fn crp_data ->
      Partners.maybe_insert_organization_data(@crp_id_key, crp_data, org_id)
    end)
  end
end
