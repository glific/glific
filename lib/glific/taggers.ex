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

  @doc """
  Lets get rid of all non valid characters. We are assuming any language and hence using unicode syntax
  and not restricting ourselves to alphanumeric
  """
  @spec string_clean(String.t()) :: String.t()
  def string_clean(str) do
    str
    |> String.replace(~r/[\p{P}\p{S}\p{Z}\p{C}]+/u, "")
    |> String.downcase()
    |> String.trim()
  end
end
