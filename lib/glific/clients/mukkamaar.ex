defmodule Glific.Clients.MukkaMaar do
  @moduledoc """
  Custom webhook implementation specific to MukkaMaar usecase
  """
  import Ecto.Query, warn: false
  alias GoogleApi.BigQuery.V2.Api.Jobs

  alias Glific.{
    Contacts.Contact,
    Flows.FlowContext,
    Repo
  }

  @registration_flow_id [822, 2801]
  @nudge_category %{
    # category_1 in nudge_category is in hours while rest are in days
    "category_1" => 20,
    # All other categories are in days
    "category_2" => 2,
    "category_3" => 3
  }

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("update_contact_categories", fields) do
    phone = String.trim(fields["phone"])

    with {:ok, contact} <- Repo.fetch_by(Contact, %{phone: phone}) do
      list =
        FlowContext
        |> where([fc], fc.contact_id == ^contact.id and is_nil(fc.completed_at))
        |> order_by([fc], desc: fc.id)
        # putting limit 2 as one active context will be of the current background flow
        |> limit(2)
        |> select([fc], %{id: fc.id, flow_id: fc.flow_id})
        |> Repo.all()

      contact
      |> Map.take([:last_message_at, :fields])
      |> set_message_category(list, length(list))
    end
  end

  def webhook("fetch_leaderboard_data", fields) do
    phone = fields["contact"]["phone"]

    with %{is_valid: true, data: data} <- fetch_bigquery_data(fields, phone) do
      data
      |> Enum.reduce(%{found: false}, fn student, acc ->
        if student["phone"] == phone,
          do: acc |> Map.merge(%{found: true, student_rank: student["StudentRank"]}),
          else: acc
      end)
    end
  end

  def webhook(_, _fields),
    do: %{}

  @spec fetch_bigquery_data(map(), String.t()) :: map()
  defp fetch_bigquery_data(fields, phone) do
    Glific.BigQuery.fetch_bigquery_credentials(fields["organization_id"])
    |> case do
      {:ok, %{conn: conn, project_id: project_id, dataset_id: _dataset_id} = _credentials} ->
        with sql <- get_report_sql(phone),
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
            %{is_valid: false, message: "No data found for phone: #{phone}"}
        end

      _ ->
        %{is_valid: false, message: "Credentials not valid"}
    end
  end

  @spec get_report_sql(String.t()) :: String.t()
  defp get_report_sql(phone),
    do: """
    SELECT * FROM `cohesive-idiom-312313.919930029265.rptLeaderBoard`
    WHERE phone = '#{phone}'
    """

  @spec set_message_category(map(), list(), non_neg_integer()) :: map()
  defp set_message_category(contact, _list, 1) do
    check_nudge_category(contact, "type 3")
  end

  defp set_message_category(contact, [_current_flow, %{flow_id: flow_id} = _flow_stucked_on], 2) do
    msg_context_category = if is_registered?(contact, flow_id), do: "type 2", else: "type 1"
    check_nudge_category(contact, msg_context_category)
  end

  @spec is_registered?(map(), pos_integer()) :: boolean()
  defp is_registered?(_contact, flow_stucked_on) when flow_stucked_on in @registration_flow_id,
    do: false

  defp is_registered?(contact, _flow_stucked_on) do
    sex = get_in(contact, [:fields, "sex", "value"])
    firstname = get_in(contact, [:fields, "first_name", "value"])
    lastname = get_in(contact, [:fields, "last_name", "value"])
    if !is_nil(sex) and !is_nil(firstname) and !is_nil(lastname), do: true, else: false
  end

  @spec check_nudge_category(map(), String.t()) :: map()
  defp check_nudge_category(contact, msg_context_category) do
    time_in_hours = Timex.diff(DateTime.utc_now(), contact.last_message_at, :hours)

    {time_since_last_msg, measure} =
      if time_in_hours < 24,
        do: {time_in_hours, :hours},
        else: {Timex.diff(DateTime.utc_now(), contact.last_message_at, :days), :days}

    nudge_category = set_contact_nudge_category(time_since_last_msg, measure)

    %{
      nudge_category: nudge_category,
      time: time_since_last_msg,
      msg_context_category: msg_context_category
    }
  end

  @spec set_contact_nudge_category(non_neg_integer(), atom()) :: String.t()
  defp set_contact_nudge_category(7, :days), do: "category 4"

  defp set_contact_nudge_category(14, :days), do: "category 5"

  defp set_contact_nudge_category(21, :days), do: "category 6"

  defp set_contact_nudge_category(28, :days), do: "category 7"

  defp set_contact_nudge_category(time_since_last_msg, measure) do
    cond do
      time_since_last_msg < @nudge_category["category_1"] and measure == :hours ->
        "category 1"

      time_since_last_msg >= 1 and time_since_last_msg < @nudge_category["category_2"] ->
        "category 2"

      time_since_last_msg >= @nudge_category["category_2"] and
          time_since_last_msg < @nudge_category["category_3"] ->
        "category 3"

      true ->
        "none"
    end
  end
end
