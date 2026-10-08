defmodule Glific.Scripts.BigQueryColumnModes do
  @moduledoc """
  Read-only check of the column modes an organization's BigQuery tables actually have, used to
  confirm a schema change reached every organization. The change itself is rolled out with the
  existing sync, which pushes `Glific.BigQuery.Schema` to each organization's tables:

      iex> Glific.Seeds.SeedsMigration.migrate_data(:sync_bigquery)

  The sync runs in the background and reports nothing per organization, so check it afterwards:

      iex> columns = %{
      ...>   "contacts" => ["phone"],
      ...>   "messages" => ["sender_phone", "receiver_phone", "contact_phone"],
      ...>   "flow_results" => ["contact_phone"],
      ...>   "profiles" => ["phone"],
      ...>   "contact_histories" => ["phone"],
      ...>   "wa_messages" => ["contact_phone"],
      ...>   "issued_certificates" => ["phone"],
      ...>   "whatsapp_forms_responses" => ["contact_phone"]
      ...> }
      iex> Glific.Scripts.BigQueryColumnModes.check_all(columns, "NULLABLE")
      [%{organization_id: 1, mismatches: [], errors: []}, ...]

      # or for a single org
      iex> Glific.Scripts.BigQueryColumnModes.check(organization_id, columns, "NULLABLE")

  An organization is done when both `mismatches` and `errors` are empty. Rerun the sync for any
  that is not.
  """

  alias Glific.{BigQuery, Repo, SafeLog, Seeds.SeedsMigration}
  alias GoogleApi.BigQuery.V2.Api.Tables

  @typedoc "Columns to check, by table id."
  @type columns :: %{String.t() => [String.t()]}

  @typedoc "Outcome for one organization."
  @type result :: %{
          organization_id: non_neg_integer(),
          mismatches: [%{table: String.t(), column: String.t(), mode: String.t() | nil}],
          errors: [%{table: String.t(), error: String.t()}]
        }

  @doc "Checks the columns for every organization with an active BigQuery credential."
  @spec check_all(columns(), String.t()) :: [result()]
  def check_all(columns, expected_mode) do
    SeedsMigration.bigquery_enabled_org_ids()
    |> Enum.map(&check(&1, columns, expected_mode))
  end

  @doc "Checks the columns of one organization's BigQuery tables against the expected mode."
  @spec check(non_neg_integer(), columns(), String.t()) :: result()
  def check(organization_id, columns, expected_mode) do
    Repo.put_process_state(organization_id)
    result = %{organization_id: organization_id, mismatches: [], errors: []}

    case BigQuery.fetch_bigquery_credentials(organization_id) do
      {:ok, credentials} ->
        Enum.reduce(columns, result, fn {table, names}, acc ->
          check_table(acc, credentials, table, names, expected_mode)
        end)

      error ->
        %{result | errors: [%{table: "*", error: SafeLog.safe_inspect(error)}]}
    end
  end

  @spec check_table(result(), map(), String.t(), [String.t()], String.t()) :: result()
  defp check_table(result, credentials, table, names, expected_mode) do
    %{conn: conn, project_id: project_id, dataset_id: dataset_id} = credentials

    case Tables.bigquery_tables_get(conn, project_id, dataset_id, table) do
      {:ok, %{schema: %{fields: fields}}} ->
        modes = Map.new(fields, &{&1.name, &1.mode || "NULLABLE"})

        mismatches =
          for name <- names,
              Map.get(modes, name) != expected_mode,
              do: %{table: table, column: name, mode: Map.get(modes, name)}

        %{result | mismatches: result.mismatches ++ mismatches}

      error ->
        %{result | errors: result.errors ++ [%{table: table, error: SafeLog.safe_inspect(error)}]}
    end
  end
end
