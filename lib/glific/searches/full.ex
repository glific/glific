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
  defp run_include_tags(query, %{filter: %{include_tags: [tag_id]}}) do
    {:ok, tag_id} = Glific.parse_maybe_integer(tag_id)

    query
    |> join(:inner, [m], mt in MessageTag, on: mt.message_id == m.id)
    |> where([_m, mt], mt.tag_id == ^tag_id)
  end

  defp run_include_tags(query, _args), do: query

  @spec run_helper(Ecto.Queryable.t(), String.t(), map()) :: Ecto.Queryable.t()
  defp run_helper(query, "", args) do
    query
    |> run_include_tags(args)
    |> offset(^args.contact_opts.offset)
    |> limit(^args.contact_opts.limit)
  end

  defp run_helper(query, term, args) do
    query
    |> join(:inner, [m], id_and_rank in matching_contact_ids_and_ranks(term, args),
      on: id_and_rank.id == m.contact_id
    )
    # eliminate any previous order by, since this takes precedence
    |> exclude(:order_by)
    |> order_by([_m, id_and_rank], desc: id_and_rank.rank)
    |> run_include_tags(args)
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
