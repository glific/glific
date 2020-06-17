defmodule Glific.Taggers.Keyword do
  @moduledoc """
  This module is user driven via keywords associated with tags. It reads in all the keywords associated
  with each tag in the DB and matches it to the input text.
  """
  alias Glific.Messages.Message
  alias Glific.Taggers

  # hardcoding greeting as 5, since this is our testcase
  # need to handle keywords in tags
  @keyword_map %{
    "hola" => 7,
    "hello" => 7,
    "hi" => 7,
    "goodmorning" => 7,
    "hey" => 7,
    "whatsup" => 7
  }

  @doc false
  @spec get_keyword_map :: %{String.t() => integer}
  def get_keyword_map, do: @keyword_map

  @doc false
  @spec tag_message(Message.t(), %{String.t() => integer}) :: {:ok, String.t()} | :error
  def tag_message(message, keyword_map) do
    message.body
    |> Taggers.string_clean()
    |> tag_body(keyword_map)
  end

  @doc false
  @spec tag_body(String.t(), %{String.t() => integer}) :: {:ok, String.t()} | :error
  def tag_body(body, keyword_map) do
    case Map.fetch(keyword_map, body) do
      {:ok, value} -> {:ok, to_string(value)}
      _ -> :error
    end
  end
end
