defmodule Glific.Search.Full do
  @moduledoc """
  Glific interface to Postgres's full text search
  """

  import Ecto.Query

  alias Glific.{
    Tags.MessageTag
  }

  @doc """
  Simple wrapper function which calls a helper function after normalizing
  and sanitizing the input. The two functions combined serve to augment
  the query with the link to the fulltext index
  """
  @spec run(Ecto.Query.t(), String.t(), map()) :: Ecto.Query.t()
  def run(query, term, args) do
    run_helper(
      query,
      normalize(term),
      args
    )
  end

  defmacro matching_contact_ids_and_ranks(term, args) do
    quote do
      fragment(
        """
        SELECT search_messages.contact_id AS id,
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

  @spec run_include_tags(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  defp run_include_tags(query, tag_ids) when is_list(tag_ids) do
    tag_ids = Enum.map(tag_ids,
        fn tag_id ->
          {:ok, tag_id} = Glific.parse_maybe_integer(tag_id)
          tag_id
        end)

    query
    |> join(:inner, [m], mt in MessageTag, on: mt.message_id == m.id)
    |> where([_m, mt], mt.tag_id in ^tag_ids)
  end

  defp run_include_tags(query, _), do: query

  @spec run_include_groups(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  defp run_include_groups(query, groupIds) do
    query
    |> join(:inner, [m], cg in ContactGroup, on: cg.contact_id == m.contact_id)
    |> where([_m, cg], cg.group_id in ^groupIds)
  end

  defp run_include_groups(query, _args), do: query


  @spec run_helper(Ecto.Queryable.t(), String.t(), map()) :: Ecto.Queryable.t()
  defp run_helper(query, "", args) do
    IO.inspect("Hell 3")
    IO.inspect(query)
    query
    |> apply_filters(args.filter)
    |> offset(^args.contact_opts.offset)
    |> limit(^args.contact_opts.limit)
  end


  defp run_helper(query, term, args) do
    IO.inspect("Hell 1")
    query
    |> join(:inner, [m], id_and_rank in matching_contact_ids_and_ranks(term, args),
      on: id_and_rank.id == m.contact_id
    )
    # eliminate any previous order by, since this takes precedence
    |> apply_filters(args)
    |> exclude(:order_by)
    |> order_by([_m, id_and_rank], desc: id_and_rank.rank)
  end

  defp apply_filters(query, filter) when is_nil(filter), do: query

  defp apply_filters(query, filter) do
    Enum.reduce(filter, query, fn
      {:include_tags, tag_ids}, query -> run_include_tags(query, tag_ids)

      {:include_groups, group_ids}, query -> run_include_groups(query, group_ids)
      _filter, query -> query
    end)
  end

  @spec normalize(String.t()) :: String.t()
  defp normalize(term) do
    term
    |> String.downcase()
    |> String.replace(~r/[\n|\t]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
