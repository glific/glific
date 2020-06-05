defmodule Glific.Search.Full do
  @moduledoc """
  Glific interface to Postgres's full text search
  """

  import Ecto.Query

  @spec run(Ecto.Query.t(), String.t()) :: Ecto.Query.t()
  def run(query, term) do
    run_helper(query, term |> normalize)
  end

  defmacro matching_contact_ids_and_ranks(term) do
    quote do
      fragment(
  """
  SELECT message_search.id AS id,
  ts_rank(
  message_search.document, plainto_tsquery(unaccent(?))
  ) AS rank
  FROM message_search
  WHERE message_search.document @@ plainto_tsquery(unaccent(?))
  OR message_search.contact_label ILIKE ?
  OR message_search.tag_label ILIKE ?
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
    from contacts in query,
      join: id_and_rank in matching_contact_ids_and_ranks(term),
      on: id_and_rank.id == contacts.id,
      order_by: [desc: id_and_rank.rank]
  end

  @spec normalize(String.t()) :: String.t()
  defp normalize(term) do
    term
    |> String.downcase
    |> String.replace(~r/[\n|\t]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim
  end

end
