defmodule Glific.AI.History do
  @moduledoc """
  The newest rows belonging to each of several parents, without one busy parent
  starving the rest.

  A single `LIMIT` cannot express this: ordered across the whole result set, one
  parent with a long history consumes the entire budget and the others come back
  empty — which reads as "this never happened" rather than "not shown here". So
  each row is ranked within its own parent and the rank is filtered afterwards,
  and every parent's true total comes back alongside, so a parent that was cut
  short says so.
  """

  import Ecto.Query

  alias Glific.Repo

  @doc """
  Up to `take` of each parent's newest rows, keyed by parent id.

  A parent with more rows than were taken is returned as
  `%{truncated: true, showing: rows, of: total}`; one returned whole is a plain
  list.
  """
  @spec newest_per_parent(
          Ecto.Queryable.t(),
          atom(),
          [atom()],
          keyword(),
          [
            non_neg_integer()
          ],
          pos_integer()
        ) :: map()
  def newest_per_parent(schema, parent, fields, order, parent_ids, take) do
    schema
    |> ranked(parent, fields, order, parent_ids)
    |> within(take)
    |> Repo.all()
    |> group(fields)
  end

  @spec ranked(Ecto.Queryable.t(), atom(), [atom()], keyword(), [non_neg_integer()]) ::
          Ecto.Query.t()
  defp ranked(schema, parent, fields, order, parent_ids) do
    from(row in schema,
      where: field(row, ^parent) in ^parent_ids,
      select: %{
        parent: field(row, ^parent),
        rank: over(row_number(), :newest_first),
        total: over(count(), :whole_parent)
      },
      windows: [
        newest_first: [partition_by: field(row, ^parent), order_by: ^order],
        whole_parent: [partition_by: field(row, ^parent)]
      ]
    )
    |> select_merge([row], map(row, ^fields))
  end

  @spec within(Ecto.Query.t(), pos_integer()) :: Ecto.Query.t()
  defp within(ranked, take), do: from(row in subquery(ranked), where: row.rank <= ^take)

  @spec group([map()], [atom()]) :: map()
  defp group(rows, fields) do
    rows
    |> Enum.group_by(& &1.parent)
    |> Map.new(fn {parent, [%{total: total} | _] = grouped} ->
      shown = Enum.map(grouped, &Map.take(&1, fields))

      {parent,
       if(total > length(shown), do: %{truncated: true, showing: shown, of: total}, else: shown)}
    end)
  end
end
