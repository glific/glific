defmodule Glific.Search.Messages do
  @moduledoc """
  Glific interface to Postgres's full text search
  """

  import Ecto.Query

  @spec run(Ecto.Query.t(), any) :: Ecto.Query.t()
  def run(query, term) do
    run_helper(query, term |> normalize)
  end

  defp run_helper(query, ""), do: query
  defp run_helper(_query, _term) do
    nil
  end

  def normalize(term) do
    term
    |> String.downcase
    |> String.replace(~r/[\n|\t]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim
  end

end
