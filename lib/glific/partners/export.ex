defmodule Glific.Partners.Export do
  @moduledoc """
  Lets do a bulk export of all data belonging to an organization, since this is API
  driven we are not streaming the output, and hence not using the streaming functionality
  of elixir
  """

  @meta [
    "languages",
    "providers"
  ]

  @tables [
    "contacts",
    "messages",
    "messages_media",
    "locations",
    "flows",
    "flow_results",
    "groups",
    "interactive_templates",
    "organizations",
    "organization_data",
    "profiles"
  ]

  @airbyte_types %{
    "bigint" => "integer",
    "timestamp without time zone" => "timestamp_without_timezone",
    "jsonb" => "object",
    "USER-DEFINED" => "string"
  }

  alias Glific.Repo

  @doc """
  Exports all the dynamic data related to contacts, fields and messages
  """
  @spec export_data(non_neg_integer, map()) :: map()
  def export_data(organization_id, opts) do
    # Add a rate limiter here, once per minute or so per organization

    # fix limit for API calls that don't adhere to it
    limit = Map.get(opts, :limit, 500)
    limit = if limit > 500, do: 500, else: limit

    opts
    |> Map.put(:limit, limit)
    |> Map.put_new(:offset, 0)
    |> Map.put_new(:end_time, DateTime.utc_now())
    |> Map.put_new(:tables, [])
    |> make_sql(organization_id)
    |> Enum.reduce(
      %{
        stats: %{},
        data: %{}
      },
      fn queries, acc -> execute(queries, acc) end
    )
  end

  @doc """
  Export the stats for all tables, so the caller can decide how to structure the
  sequence of requests to get all the data
  """
  @spec export_stats(non_neg_integer(), map()) :: map()
  def export_stats(organization_id, opts) do
    opts
    |> Map.put_new(:tables, [])
    |> tables()
    |> Enum.reduce(
      %{},
      fn table, acc ->
        table
        |> stats_query(organization_id, opts[:start_time])
        |> add_map(acc, table, true)
      end
    )
  end

  @doc """
  Export the global config tables which are shared by all organizations. There
  is nothing secret in there, but help orgs with referential integrity
  """
  @spec export_config :: map()
  def export_config do
    (@tables ++ @meta)
    |> Enum.reduce(%{}, fn table, acc ->
      data =
        table
        |> config_query()
        |> Repo.query!([], timeout: 60_000, skip_organization_id: true)
        |> Map.get(:rows)
        |> transform_data()

      Map.put(acc, table, %{"schema" => data})
    end)
    |> Map.put("tables", @tables)
    |> Map.put("config", @meta)
  end

  @spec transform_data(list()) :: map()
  defp transform_data(data) do
    data
    |> Enum.reduce(
      %{},
      fn [column_name, data_type, column_default], acc ->
        airbyte_data_type = Map.get(@airbyte_types, data_type, data_type)

        # sending a list of lists, since json does not understand elixir tuples
        Map.put(acc, column_name, [airbyte_data_type, column_default])
      end
      )
      |> Poison.encode!()
  end

  @spec config_query(String.t()) :: String.t()
  defp config_query(table),
    do: """
    SELECT column_name, data_type, column_default
    FROM information_schema.columns
    WHERE table_name = '#{table}'
    """

  @spec add_start(DateTime.t() | nil) :: String.t()
  defp add_start(nil), do: ""
  defp add_start(time), do: " AND updated_at >= '#{time}'"

  @spec stats_query(String.t(), non_neg_integer(), DateTime.t() | nil) :: String.t()
  defp stats_query(table, organization_id, start_time),
    do: """
      SELECT count(*), min(updated_at), max(updated_at)
      FROM #{table}
      WHERE organization_id = #{organization_id}
      #{add_start(start_time)}
    """

  @spec execute(tuple, map()) :: map()
  defp execute({table, data, stats}, acc) do
    acc
    |> Map.put(:stats, add_map(stats, acc.stats, table, true))
    |> Map.put(:data, add_map(data, acc.data, table))
  end

  @spec make_sql(map, non_neg_integer) :: list
  defp make_sql(opts, organization_id) do
    opts
    |> tables()
    |> Enum.reduce(
      [],
      fn table, acc ->
        [sql(table, organization_id, opts) | acc]
      end
    )
    |> Enum.reverse()
  end

  @spec sql(String.t(), non_neg_integer, map) :: tuple
  defp sql(table, organization_id, opts) do
    q = query(table, organization_id, opts)

    {
      table,
      "SELECT JSON_AGG(t) FROM (SELECT * #{q}) t",
      "SELECT count(*), min(updated_at), max(updated_at) #{q}"
    }
  end

  @spec query(String.t(), non_neg_integer, map) :: String.t()
  defp query("organizations", organization_id, _opts),
    do: """
    FROM organizations
    WHERE organization_id = #{organization_id}
    """

  defp query(table, organization_id, opts) do
    %{
      start_time: start_time,
      end_time: end_time,
      limit: limit,
      offset: offset
    } = opts

    """
    FROM #{table}
    WHERE organization_id = #{organization_id}
    AND #{table}.updated_at >= '#{start_time}'
    AND #{table}.updated_at < '#{end_time}'
    LIMIT #{limit}
    OFFSET #{offset}
    """
  end

  # filter the tables to include only valid table required by the caller
  @spec tables(map) :: list
  defp tables(opts) do
    if opts.tables == [],
      do: @tables,
      else:
        @tables
        |> MapSet.new()
        |> MapSet.intersection(MapSet.new(opts.tables))
        |> MapSet.to_list()
  end

  @spec flatten(list | String.t(), boolean()) :: any()
  defp flatten(rows, false) when is_list(rows),
    do: rows |> get_in([Access.at(0)]) |> then(&if is_nil(&1), do: [], else: &1)

  defp flatten(rows, false), do: rows
  defp flatten(rows, true), do: rows

  @spec add_map(String.t(), map(), String.t(), boolean) :: map()
  defp add_map(query, acc, table, is_flatten \\ false) do
    data = Repo.query!(query, [], timeout: 60_000, skip_organization_id: true)

    if is_list(data.rows) && length(data.rows) > 0,
      do: Map.put(acc, table, flatten(hd(data.rows), is_flatten)),
      else: acc
  end
end
