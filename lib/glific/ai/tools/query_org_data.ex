defmodule Glific.AI.Tools.QueryOrgData do
  @moduledoc """
  Runs an allow-listed, read-only query against one organisation data table, via
  `Glific.ChatbotDiagnose.run/3`, scoped to `ctx.organization_id`.

  ## Why `required_role/0` is `:manager`

  `ChatbotDiagnose.run/3` builds bare `Ecto.Query`s and never calls `Repo.add_permission/3`, so
  everything it returns is scoped by organisation but **not** by group permission — a restricted
  `:staff` user who can normally only see contacts in their assigned groups would, through this
  tool, see every contact in the organisation. Gating at `:manager` closes that gap today rather
  than pretending it does not exist: `Repo.skip_permission?/1` already returns `true` for anyone
  who is not both `is_restricted` and `:staff` (see `Glific.AI.Actor`), so a manager was never
  group-permission-filtered in the first place — the gate costs a manager nothing they had.
  Teaching `ChatbotDiagnose` to call `Repo.add_permission/3` for the tables that have
  group-permission functions (contacts, groups, flows, ...) is a tracked follow-up; this gate is
  the stop-gap until that lands.
  """

  use Glific.AI.Tool

  alias Glific.AI.Tool.Context
  alias Glific.ChatbotDiagnose

  @tables ChatbotDiagnose.tables()

  @doc false
  @spec name() :: String.t()
  @impl true
  def name, do: "query_org_data"

  @doc false
  @spec description() :: String.t()
  @impl true
  def description,
    do:
      "Queries one organisation data table, read-only, scoped to the current organisation. " <>
        "Call describe_table first to see the table's field names. Results are capped and can " <>
        "be filtered by a time range."

  @doc false
  @spec parameters() :: keyword()
  @impl true
  def parameters do
    [
      table: [type: {:in, @tables}, required: true, doc: "The table to query."],
      fields: [
        type: {:list, :string},
        doc: "Field names to return. Defaults to every allow-listed field on the table."
      ],
      filters: [type: {:map, :string, :any}, doc: "Equality filters, field name to value."],
      limit: [type: :pos_integer, doc: "Maximum rows to return. Capped at 50."],
      time_range: [
        type: :string,
        doc: ~s(How far back to filter by inserted_at, e.g. "24h" or "7d". Omit for no filter.)
      ]
    ]
  end

  @doc false
  @spec required_role() :: atom()
  @impl true
  def required_role, do: :manager

  @doc false
  @spec run(map(), Context.t()) :: {:ok, term()} | {:error, String.t()}
  @impl true
  def run(%{"table" => table} = args, %Context{organization_id: organization_id})
      when is_binary(table) do
    # ChatbotDiagnose.run/3 treats an unknown table as an empty result, not an error (it logs
    # and moves on, since it also serves multi-table Dify requests where one bad table shouldn't
    # fail the rest) — so table membership is checked here, ahead of the delegation, to give the
    # model an explicit, actionable error instead of a silently empty result.
    if table in ChatbotDiagnose.tables() do
      table_opts =
        %{}
        |> maybe_put("fields", args["fields"])
        |> maybe_put("filters", args["filters"])
        |> maybe_put("limit", args["limit"])

      rows =
        %{table => table_opts}
        |> ChatbotDiagnose.run(args["time_range"], organization_id)
        |> Map.fetch!(table)

      {:ok, rows}
    else
      {:error, "Unknown table: #{table}"}
    end
  end

  def run(_args, %Context{}), do: {:error, "table is required"}

  @spec maybe_put(map(), String.t(), term()) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
