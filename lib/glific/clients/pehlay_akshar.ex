defmodule Glific.Clients.PehlayAkshar do
  @moduledoc """
  Custom webhook implementation specific to PehlayAkshar use case
  """

  alias Glific.{
    Partners,
    Partners.OrganizationData,
    Repo,
    Sheets.ApiClient,
    Templates.SessionTemplate
  }

  alias GoogleApi.BigQuery.V2.Api.Jobs

  @paf %{
    "dataset" => "918657546231",
    "rank_table" => "leaderboard"
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
        Map.get(organization_data.json, today, %{})
        |> Map.put("organization_id", org_id)

      _ ->
        %{}
    end
  end

  def webhook("get_question_buttons", fields) do
    buttons =
      fields["question"]
      |> String.split("|")
      |> Enum.with_index()
      |> Enum.map(fn {answer, index} -> {"button_#{index + 1}", String.trim(answer)} end)
      |> Enum.into(%{})

    %{
      buttons: buttons,
      button_count: length(Map.keys(buttons)),
      is_valid: true
    }
  end

  def webhook("check_response", fields) do
    %{
      response: String.equivalent?(fields["correct_response"], fields["user_response"])
    }
  end

  def webhook("fetch_leaderboard_data", fields) do
    with %{is_valid: true, data: data} <- fetch_bigquery_data(fields, :overall) do
      formatted_data = format_leadership_data(data)

      %{
        found: true,
        ranking_list: formatted_data
      }
    end
  end

  def webhook("fetch_individual_rank", fields) do
    with %{is_valid: true, data: data} <- fetch_bigquery_data(fields, :individual),
         [%{"Rank" => rank}] <- data do
      %{
        found: true,
        individual_rank: rank
      }
    end
  end

  def webhook(_, _) do
    raise "Unknown webhook"
  end

  def format_leadership_data(data) do
    Enum.with_index(data)
    |> Enum.map(fn {user, index} ->
      name = user["name"]
      wardname = user["wardname"]
      score = user["score"] || "0"
      count = index + 1
      "#{count}. #{name} - #{wardname} - (#{score} points)\n"
    end)
  end

  @spec load_sheet(non_neg_integer()) :: :ok
  defp load_sheet(org_id) do
    ApiClient.get_csv_content(url: @sheets.content_sheet)
    |> Enum.reduce(%{}, fn {_, row}, acc ->
      Map.put(acc, row["date"], row)
    end)
    |> then(&Partners.maybe_insert_organization_data("content_sheet", &1, org_id))

    :ok
  end

  @doc """
    get template for IEX
  """
  @spec template(String.t(), non_neg_integer()) :: binary
  def template(template_label, organization_id) do
    %{
      uuid: fetch_template_uuid(template_label, organization_id),
      name: template_label,
      variables: ["@contact.name"],
      expression: nil
    }
    |> Jason.encode!()
  end

  def send_template(uuid, variables) do
    variables_list = Enum.map(variables, &to_string/1)

    %{
      uuid: uuid,
      variables: variables_list,
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

  @spec fetch_bigquery_data(map(), String.t()) :: map()
  defp fetch_bigquery_data(fields, query_type) do
    Glific.BigQuery.fetch_bigquery_credentials(fields["organization_id"])
    |> case do
      {:ok, %{conn: conn, project_id: project_id, dataset_id: _dataset_id} = _credentials} ->
        with sql <- get_report_sql(query_type, fields),
             {:ok, %{totalRows: total_rows} = response} <-
               Jobs.bigquery_jobs_query(conn, project_id,
                 body: %{query: sql, useLegacySql: false, timeoutMs: 120_000}
               ),
             true <- total_rows != "0" do
          data =
            response.rows
            |> Enum.map(fn row ->
              row.f
              |> Enum.with_index()
              |> Enum.reduce(%{}, fn {cell, i}, acc ->
                acc |> Map.put_new("#{Enum.at(response.schema.fields, i).name}", cell.v)
              end)
            end)

          %{is_valid: true, data: data}
        else
          _ ->
            %{is_valid: false, message: "No data found for phone: #{fields["contact"]["phone"]}"}
        end

      _ ->
        %{is_valid: false, message: "Credentials not valid"}
    end
  end

  defp get_report_sql(:overall, _fields) do
    """
    SELECT *
    FROM `#{@paf["dataset"]}.#{@paf["rank_table"]}` LIMIT 10;
    """
  end

  defp get_report_sql(:individual, fields) do
    phone = fields["contact"]["phone"]

    """
    SELECT Rank FROM `#{@paf["dataset"]}.#{@paf["rank_table"]}`
    WHERE phone = '#{phone}';
    """
  end
end
