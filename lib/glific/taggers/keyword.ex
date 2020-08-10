defmodule Glific.Taggers.Keyword do
  @moduledoc """
  This module is user driven via keywords associated with tags. It reads in all the keywords associated
  with each tag in the DB and matches it to the input text.
  """
  alias Glific.Messages.Message

  # hardcoding greeting as 5, since this is our testcase
  # need to handle keywords in tags

  @doc false
  @spec get_keyword_map :: %{String.t() => integer}
  def get_keyword_map, do: Glific.Tags.keyword_map()

  @doc false
  @spec tag_message(Message.t(), %{String.t() => integer}) :: {:ok, String.t()} | :error
  def tag_message(message, keyword_map) do
    message.body
    |> Glific.string_clean()
    |> tag_body(keyword_map)
  end

  @doc false
  @spec tag_body(String.t(), %{String.t() => integer}) :: {:ok, integer} | :error
  def tag_body(body, keyword_map),
    do: Map.fetch(keyword_map, body)
end
