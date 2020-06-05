defmodule Glific.Search.Messages do
  @moduledoc """
  Glific interface to Postgres's full text search
  """

  import Ecto.Query

  @spec run(Ecto.Query.t(), any) :: Ecto.Query.t()
  def run(query, search_string) do
    run_helper(query, search_string |> normalize)
  end

  defmacro matching_contact_ids_and_ranks(search_string) do
    quote do
      fragment(
  """
  SELECT message_search.id AS id,
  ts_rank(
  message_search.document, plainto_tsquery(unaccent(?))
  ) AS rank
  FROM message_search
  WHERE message_search.document @@ plainto_tsquery(unaccent(?))
  OR message_search.name ILIKE ?
  """,
        ^unquote(search_string),
        ^unquote(search_string),
        ^"%#{unquote(search_string)}%"
      )
    end
  end

  defp run_helper(query, ""), do: query
  defp run_helper(query, search_string) do
    from contacts in query,
      join: id_and_rank in matching_contact_ids_and_ranks(search_string),
      on: id_and_rank.id == contacts.id,
      order_by: [desc: id_and_rank.rank]
  end

  def normalize(search_string) do
    search_string
    |> String.downcase
    |> String.replace(~r/[\n|\t]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim
  end

end
