defmodule Glific.Search.Full do
  @moduledoc """
  Glific interface to Postgres's full text search
  """

  import Ecto.Query

  alias Glific.{
    Groups.ContactGroup
  }

  @doc """
  Simple wrapper function which calls a helper function after normalizing
  and sanitizing the input. The two functions combined serve to augment
  the query with the link to the fulltext index
  """
  @spec run(Ecto.Query.t(), String.t(), map()) :: Ecto.Query.t()
  def run(query, term, args) do
    query
    |> block_contacts()
    |> run_helper(
      normalize(term),
      args
    )
  end

  @spec block_contacts(Ecto.Query.t()) :: Ecto.Query.t()
  defp block_contacts(query) do
    query
    |> where([c: c], c.status != ^:blocked)
  end

  defmacro matching_contact_ids_and_ranks(term, args) do
    quote do
      fragment(
        """
        SELECT search_messages.contact_id,
        ts_rank(
        search_messages.document, plainto_tsquery(unaccent(?))
        ) AS rank
        FROM search_messages
        WHERE search_messages.document @@ plainto_tsquery(unaccent(?))
        OR search_messages.phone ILIKE ?
        OR search_messages.name ILIKE ?
        OR ? ILIKE ANY(tag_label)
        OFFSET ?
        LIMIT ?
        """,
        ^unquote(term),
        ^unquote(term),
        ^"%#{unquote(term)}%",
        ^"%#{unquote(term)}%",
        ^"%#{unquote(term)}%",
        ^unquote(args).contact_opts.offset,
        ^unquote(args).contact_opts.limit
      )
    end
  end

  @spec run_include_groups(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  defp run_include_groups(query, group_ids) when is_list(group_ids) and group_ids != [] do
    group_ids =
      Enum.map(group_ids, fn group_id ->
        {:ok, group_id} = Glific.parse_maybe_integer(group_id)
        group_id
      end)

    query
    |> join(:inner, [m: m], cg in ContactGroup, as: :cg, on: cg.contact_id == m.contact_id)
    |> where([cg: cg], cg.group_id in ^group_ids)
  end

  defp run_include_groups(query, _args), do: query

  @spec run_helper(Ecto.Queryable.t(), String.t(), map()) :: Ecto.Queryable.t()
  defp run_helper(query, term, args) when term != nil and term != "" do
    query
    |> join(:inner, [m: m], id_and_rank in matching_contact_ids_and_ranks(term, args),
      as: :id_and_rank,
      on: id_and_rank.contact_id == m.contact_id
    )
    |> apply_filters(args.filter)
    # eliminate any previous order by, since this takes precedence
    |> exclude(:order_by)
    |> order_by([id_and_rank: id_and_rank], desc: id_and_rank.rank)
  end

  defp run_helper(query, _, args) do
    query
    |> apply_filters(args.filter)
    |> offset(^args.contact_opts.offset)
    |> limit(^args.contact_opts.limit)
  end

  @spec apply_filters(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  defp apply_filters(query, filter) when is_nil(filter), do: query

  defp apply_filters(query, filter) do
    Enum.reduce(filter, query, fn
      {:include_groups, group_ids}, query ->
        query |> run_include_groups(group_ids)

      {:date_range, dates}, query ->
        query |> run_date_range(dates[:from], dates[:to])

      {_key, _value}, query ->
        query
    end)
  end

  @spec normalize(String.t()) :: String.t()
  defp normalize(term) when term != "" and term != nil do
    term
    |> String.downcase()
    |> String.replace(~r/[\n|\t]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp normalize(term), do: term

  # Filter based on the date range
  @spec run_date_range(Ecto.Queryable.t(), DateTime.t(), DateTime.t()) :: Ecto.Queryable.t()
  defp run_date_range(query, nil, nil), do: query

  defp run_date_range(query, nil, to) do
    query
    |> where([c: c], c.last_message_at <= ^(Timex.to_datetime(to) |> Timex.end_of_day()))
  end

  defp run_date_range(query, from, nil) do
    query
    |> where([c: c], c.last_message_at >= ^Timex.to_datetime(from))
  end

  defp run_date_range(query, from, to) do
    query
    |> where(
      [c: c],
      c.last_message_at >= ^Timex.to_datetime(from) and
        c.last_message_at <= ^(Timex.to_datetime(to) |> Timex.end_of_day())
    )
  end
end
