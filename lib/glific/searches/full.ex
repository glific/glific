defmodule Glific.Search.Full do
  @moduledoc """
  Glific interface to Postgres's full text search
  """

  import Ecto.Query

  alias Glific.{
    Messages.Message,
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

  @spec run_helper(Ecto.Query.t(), String.t(), map()) :: Ecto.Query.t()
  defp run_helper(query, "", %{filter: %{include_tags: [tag_id]}} = args) do
    {:ok, tag_id} = Glific.parse_maybe_integer(tag_id)

    query
    |> join(:inner, [c], m in Message, on: m.contact_id == c.id)
    |> join(:inner, [c, m], mt in MessageTag, on: mt.message_id == m.id)
    |> where([_c, _m, mt], mt.tag_id == ^tag_id)
    |> offset(^args.contact_opts.offset)
    |> limit(^args.contact_opts.limit)
    |> order_by([_c, m, _mt], desc: m.updated_at)
  end

  defp run_helper(query, "", args) do
    query
    |> offset(^args.contact_opts.offset)
    |> limit(^args.contact_opts.limit)
  end

  defp run_helper(query, term, args) do
    from q in query,
      join: id_and_rank in matching_contact_ids_and_ranks(term, args),
      on: id_and_rank.id == q.id,
      order_by: [desc: id_and_rank.rank]
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
