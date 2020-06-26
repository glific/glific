defmodule Glific.Search.Full do
  @moduledoc """
  Glific interface to Postgres's full text search
  """

  import Ecto.Query

  @doc """
  Simple wrapper function which calls a helper function after normalizing
  and sanitizing the input. The two functions combined serve to augment
  the query with the link to the fulltext index
  """
  @spec run(Ecto.Query.t(), String.t()) :: Ecto.Query.t()
  def run(query, term) do
    run_helper(
      query,
      term |> normalize
    )
  end

  defmacro matching_contact_ids_and_ranks(term) do
    quote do
      fragment(
        """
        SELECT search_messages.contact_id AS id,
        ts_rank(
        search_messages.document, plainto_tsquery(unaccent(?))
        ) AS rank
        FROM search_messages
        WHERE search_messages.document @@ plainto_tsquery(unaccent(?))
        OR search_messages.name ILIKE ?
        OR ? ILIKE ANY(tag_label)
        """,
        ^unquote(term),
        ^unquote(term),
        ^"%#{unquote(term)}%",
        ^"%#{unquote(term)}%"
      )
    end
  end

  @spec run_helper(Ecto.Query.t(), String.t()) :: Ecto.Query.t()
  defp run_helper(query, ""), do: query

  defp run_helper(query, term) do
    from q in query,
      join: id_and_rank in matching_contact_ids_and_ranks(term),
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
