defmodule Glific.Clients.PehlayAkshar do
  @moduledoc """
  Custom webhook implementation specific to PehlayAkshar use case
  """

  alias Glific.{
    Messages,
    Partners,
    Partners.OrganizationData,
    Repo,
    Sheets.ApiClient,
    Templates.SessionTemplate
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

  def webhook("fetch_advisory_content", fields) do
    today = Timex.format!(DateTime.utc_now(), "{D}/{M}/{YYYY}")
    org_id = Glific.parse_maybe_integer!(fields["organization_id"])

    Repo.fetch_by(OrganizationData, %{
      organization_id: org_id,
      key: "content_sheet"
    })
    |> case do
      {:ok, organization_data} ->
        Map.get(organization_data.json, today, %{}) |> Map.put("organization_id", org_id)

      _ ->
        %{}
    end
  end

  def webhook(_, _) do
    raise "Unknown webhook"
  end

  # @spec load_sheet(String.t(), String.t(), non_neg_integer()) :: :ok
  def load_sheet(org_id) do
    ApiClient.get_csv_content(url: @sheets.content_sheet)
    |> Enum.reduce(%{}, fn {_, row}, acc ->
      Map.put(acc, row["date"], row)
    end)
    |> then(&Partners.maybe_insert_organization_data("content_sheet", &1, org_id))
  end

  @doc """
    get template for IEX
  """
  @spec template(String.t(), String.t(), non_neg_integer()) :: binary
  def template(template_label, media_url, organization_id) do
    %{
      uuid: fetch_template_uuid(template_label, organization_id),
      name: template_label,
      variables: ["@contact.name"],
      expression: nil
    }
    |> Jason.encode!()
  end

  defp fetch_template_uuid(template_label, organization_id) do
    Repo.fetch_by(SessionTemplate, %{
      shortcode: template_label,
      is_hsm: true,
      organization_id: organization_id
    })
    |> case do
      {:ok, template} -> template.uuid
      _ -> nil
    end
  end
end
