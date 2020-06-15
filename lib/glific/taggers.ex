defmodule Glific.Taggers do
  @moduledoc """
  The API for a generic tagging system on messages that coordinate with different types of taggers.
  The proposed taggers are:
    Numeric
    Keyword
    Emojis
      Positive
      Negative
    Automated
      Compliments
      Good Bye
      Greeting
      Thank You
      Welcome
      Spam
  """

  alias Glific.{
    Messages.Message,
    Taggers.Numeric
  }

  @spec tag_message(Message.t(), %{String.t() => integer}) :: {:ok, String.t()} | {:error, nil}
  def tag_message(message, numeric_map) do
    Numeric.tag_message(message, numeric_map)
  end

  def string_clean(str) do
    str
    |> String.replace(~r/[\p{P}\p{S}\p{Z}\p{C}]+/, "")
    |> String.downcase
    |> String.trim
  end

end
